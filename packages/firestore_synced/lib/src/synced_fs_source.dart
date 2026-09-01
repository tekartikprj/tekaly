import 'package:tekaly_firestore_synced/src/synced_fs_change.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_document.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_meta.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_refs.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// Default number of entries read in one change log step.
const syncedFsDefaultStepLimit = 100;

/// Maximum number of document references read at once.
const syncedFsGetAllChunkSize = 100;

/// A point in time snapshot of some documents of a synced collection.
class SyncedFsSnapshot {
  /// Existing documents, by document id, without the `synced` information.
  final Map<String, Model> docs;

  /// Requested (or previously known) ids that do not exist any more, either
  /// deleted or never created.
  final List<String> missing;

  /// The change id the snapshot can be resumed from.
  ///
  /// Read *before* the documents so that any concurrent modification is
  /// replayed by the following incremental synchronization.
  final int? lastChangeId;

  /// Snapshot.
  SyncedFsSnapshot({
    required this.docs,
    required this.missing,
    required this.lastChangeId,
  });

  @override
  String toString() =>
      'SyncedFsSnapshot(${docs.length} doc(s), ${missing.length} missing, '
      'lastChangeId: $lastChangeId)';
}

/// Read only view of a synced firestore collection, everything a consumer
/// (a local sdb mirror, another backend, ...) needs to stay in sync.
abstract class SyncedFsSource {
  /// Identifies the source, typically the collection path. Stored locally to
  /// detect that a local mirror is bound to another source.
  String get sourceId;

  /// The collection meta information, null if never written.
  Future<SyncedFsMetaInfoRecord?> getMetaInfo();

  /// "Give me everything newer than modification number X".
  ///
  /// Entries are ordered by change id. [afterChangeId] is exclusive.
  Future<SyncedFsChangeList> getChangeList({int? afterChangeId, int? limit});

  /// "Give me a full snapshot of these document ids", or of the whole
  /// collection when [docIds] is null.
  Future<SyncedFsSnapshot> getSnapshot({List<String>? docIds});

  /// Close the source.
  Future<void> close();
}

/// Read all the changes after [afterChangeId], in [stepLimit] steps.
extension SyncedFsSourceExt on SyncedFsSource {
  /// Read all the changes after [afterChangeId].
  Future<SyncedFsChangeList> getAllChangeList({
    int? afterChangeId,
    int? stepLimit,
  }) async {
    var list = <CvSyncedFsChangeRecord>[];
    var lastChangeId = afterChangeId;
    while (true) {
      var next = await getChangeList(
        afterChangeId: lastChangeId,
        limit: stepLimit ?? syncedFsDefaultStepLimit,
      );
      if (next.isEmpty) {
        break;
      }
      list.addAll(next.list);
      lastChangeId = next.lastChangeId;
    }
    return SyncedFsChangeList(list, lastChangeId);
  }
}

/// Firestore implementation of [SyncedFsSource], read only.
///
/// Safe to use from a client with read only rules on the collection, its
/// change log and its meta document.
class SyncedFsFirestoreSource implements SyncedFsSource {
  /// Firestore instance.
  final Firestore firestore;

  /// Collection references.
  final SyncedFsCollectionRefs refs;

  /// Source on the collection at [path].
  SyncedFsFirestoreSource({required this.firestore, required String path})
    : refs = SyncedFsCollectionRefs(path: path);

  /// Source on existing [refs].
  SyncedFsFirestoreSource.fromRefs({
    required this.firestore,
    required this.refs,
  }) {
    cvInitSyncedFsBuilders();
  }

  @override
  String get sourceId => refs.path;

  @override
  Future<SyncedFsMetaInfoRecord?> getMetaInfo() async {
    var meta = await firestore.refGet(refs.metaInfoDocRef);
    return meta.exists ? meta : null;
  }

  @override
  Future<SyncedFsChangeList> getChangeList({
    int? afterChangeId,
    int? limit,
  }) async {
    var query = refs.changesCollection.query().orderBy(changeChangeIdFieldKey);
    if (afterChangeId != null) {
      query = query.where(changeChangeIdFieldKey, isGreaterThan: afterChangeId);
    }
    query = query.limit(limit ?? syncedFsDefaultStepLimit);
    var list = await query.get(firestore);
    return SyncedFsChangeList(list, list.lastOrNull?.changeId.v);
  }

  @override
  Future<SyncedFsSnapshot> getSnapshot({List<String>? docIds}) async {
    /// Read the resume point first, so that a concurrent modification is
    /// replayed by the next incremental synchronization.
    var lastChangeId = (await getMetaInfo())?.lastChangeId.v;
    var docs = <String, Model>{};
    var missing = <String>[];
    if (docIds == null) {
      await for (var snapshot in scanCollection()) {
        var map = snapshot.dataOrNull;
        if (map == null || map.syncedIsDeleted) {
          missing.add(snapshot.ref.id);
        } else {
          docs[snapshot.ref.id] = map.withoutSyncedInfo;
        }
      }
    } else {
      for (var chunk in _chunks(docIds, syncedFsGetAllChunkSize)) {
        var snapshots = await firestore.getAll(
          chunk.map((id) => refs.collection.doc(id).raw(firestore)).toList(),
        );
        for (var snapshot in snapshots) {
          var map = snapshot.exists ? snapshot.data : null;
          if (map == null || map.syncedIsDeleted) {
            missing.add(snapshot.ref.id);
          } else {
            docs[snapshot.ref.id] = map.withoutSyncedInfo;
          }
        }
      }
    }
    return SyncedFsSnapshot(
      docs: docs,
      missing: missing,
      lastChangeId: lastChangeId,
    );
  }

  /// Walk the collection ordered by modification number, in pages of
  /// [stepLimit] documents.
  ///
  /// Documents without a modification number are *not* returned (firestore
  /// excludes documents missing the ordered field), use
  /// `SyncedFsChangeLogRebuilder.stampMissingChangeIds` to fix them.
  Stream<DocumentSnapshot> scanCollection({
    int? afterChangeId,
    int? stepLimit,
  }) async* {
    var lastChangeId = afterChangeId;
    var limit = stepLimit ?? syncedFsDefaultStepLimit;
    while (true) {
      var query = firestore
          .collection(refs.path)
          .orderBy(syncedChangeIdFieldPath)
          .limit(limit);
      if (lastChangeId != null) {
        query = query.where(
          syncedChangeIdFieldPath,
          isGreaterThan: lastChangeId,
        );
      }
      var snapshots = (await query.get()).docs;
      if (snapshots.isEmpty) {
        break;
      }
      for (var snapshot in snapshots) {
        yield snapshot;
      }
      var next = snapshots.last.data.syncedChangeIdOrNull;
      if (next == null || next == lastChangeId) {
        break;
      }
      lastChangeId = next;
    }
  }

  @override
  Future<void> close() async {}

  @override
  String toString() => 'SyncedFsFirestoreSource(${refs.path})';
}

Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
  for (var i = 0; i < list.length; i += size) {
    yield list.sublist(i, i + size > list.length ? list.length : i + size);
  }
}
