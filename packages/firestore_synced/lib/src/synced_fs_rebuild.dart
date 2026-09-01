import 'package:tekaly_firestore_synced/src/synced_fs_change.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_document.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_meta.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_refs.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_source.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_trigger.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// What a change log rebuild or reconciliation did.
class SyncedFsRebuildResult {
  /// Documents walked.
  final int scannedCount;

  /// Change log entries appended.
  final int addedCount;

  /// Documents that had no modification number and got one.
  final int stampedCount;

  /// Highest modification number reached, null when nothing was scanned.
  final int? lastChangeId;

  /// False when the run stopped on its limit and must be resumed.
  final bool complete;

  /// Result.
  SyncedFsRebuildResult({
    required this.scannedCount,
    required this.addedCount,
    required this.stampedCount,
    required this.lastChangeId,
    required this.complete,
  });

  @override
  String toString() =>
      'SyncedFsRebuildResult(scanned: $scannedCount, added: $addedCount, '
      'stamped: $stampedCount, lastChangeId: $lastChangeId, '
      'complete: $complete)';
}

/// Rebuilds the change log of a synced collection from the collection itself.
///
/// This is the safety net of the design: the change log is normally fed in the
/// document write transaction ([SyncedFsCollection]) or by a cloud function
/// ([SyncedFsCollectionTrigger]), both of which can fail or be skipped. Run
/// [rebuild] on demand (`since modification number X`) or [reconcile] from a
/// cron to emit whatever is missing.
///
/// Note that a rebuild produces a *compacted* log: only the current
/// modification number of each document can be recovered, superseded ones stay
/// missing, which is harmless for a consumer asking for "everything newer than
/// X". Hard deletions cannot be recovered at all, which is why
/// [SyncedFsCollection.deleteDoc] writes a tombstone instead.
class SyncedFsChangeLogRebuilder {
  /// The change log writer.
  final SyncedFsChangeWriter writer;

  /// Read only view of the collection.
  final SyncedFsFirestoreSource source;

  /// Firestore instance.
  Firestore get firestore => writer.firestore;

  /// Collection, change log and meta references.
  SyncedFsCollectionRefs get refs => writer.refs;

  /// Rebuilder on the collection at [path].
  SyncedFsChangeLogRebuilder({
    required Firestore firestore,
    required String path,
    bool includeData = true,
  }) : this.fromWriter(
         SyncedFsChangeWriter(
           firestore: firestore,
           path: path,
           includeData: includeData,
         ),
       );

  /// Rebuilder on an existing [writer].
  SyncedFsChangeLogRebuilder.fromWriter(this.writer)
    : source = SyncedFsFirestoreSource.fromRefs(
        firestore: writer.firestore,
        refs: writer.refs,
      );

  /// Rebuild the change log for everything modified after [sinceChangeId].
  ///
  /// When [sinceChangeId] is null the resume point of the previous complete
  /// rebuild (`changeLogChangeId` in the meta document) is used, so a cron can
  /// simply call `rebuild()`. Pass 0 to walk the whole collection.
  ///
  /// [limit] bounds the number of documents walked, the result then reports
  /// `complete: false` and the run must be resumed with the returned
  /// `lastChangeId`.
  Future<SyncedFsRebuildResult> rebuild({
    int? sinceChangeId,
    int? limit,
    int? stepLimit,
  }) async {
    var meta = await source.getMetaInfo();
    var startLastChangeId = meta?.lastChangeId.v ?? 0;
    sinceChangeId ??= meta?.changeLogChangeId.v;

    var scannedCount = 0;
    var addedCount = 0;
    var complete = true;
    var lastChangeId = sinceChangeId;

    await for (var snapshot in source.scanCollection(
      afterChangeId: sinceChangeId,
      stepLimit: stepLimit,
    )) {
      if (limit != null && scannedCount >= limit) {
        complete = false;
        break;
      }
      scannedCount++;
      var added = await _ensureChange(
        snapshot,
        origin: SyncedFsChangeOrigin.rebuild,
      );
      if (added) {
        addedCount++;
      }
      lastChangeId = snapshot.data.syncedChangeIdOrNull ?? lastChangeId;
    }

    if (complete) {
      /// Every document modified up to [startLastChangeId] now has an entry,
      /// the next rebuild can resume from there.
      await _updateMeta((meta) => meta.changeLogChangeId.v = startLastChangeId);
    }
    return SyncedFsRebuildResult(
      scannedCount: scannedCount,
      addedCount: addedCount,
      stampedCount: 0,
      lastChangeId: lastChangeId,
      complete: complete,
    );
  }

  /// Scheduled reconciliation: walk the documents updated after
  /// [sinceTimestamp] (or in the last [since] duration) and emit whatever
  /// change log entry is missing.
  ///
  /// Cheaper than a full [rebuild] and meant to run from a cron a bit more
  /// often than the trigger failure window. When neither [sinceTimestamp] nor
  /// [since] is given, the previous reconciliation time is used.
  Future<SyncedFsRebuildResult> reconcile({
    Timestamp? sinceTimestamp,
    Duration? since,
    int? limit,
    int? stepLimit,
  }) async {
    var meta = await source.getMetaInfo();
    if (sinceTimestamp == null && since != null) {
      sinceTimestamp = Timestamp.fromDateTime(DateTime.now().subtract(since));
    }
    sinceTimestamp ??= meta?.lastReconcileTimestamp.v;
    var startTimestamp = Timestamp.now();

    var scannedCount = 0;
    var addedCount = 0;
    var complete = true;
    int? lastChangeId;
    var lastTimestamp = sinceTimestamp;

    while (true) {
      var query = firestore
          .collection(refs.path)
          .orderBy(syncedTimestampFieldPath)
          .limit(stepLimit ?? syncedFsDefaultStepLimit);
      if (lastTimestamp != null) {
        query = query.where(
          syncedTimestampFieldPath,
          isGreaterThan: lastTimestamp,
        );
      }
      var snapshots = (await query.get()).docs;
      if (snapshots.isEmpty) {
        break;
      }
      for (var snapshot in snapshots) {
        if (limit != null && scannedCount >= limit) {
          complete = false;
          break;
        }
        scannedCount++;
        var added = await _ensureChange(
          snapshot,
          origin: SyncedFsChangeOrigin.reconcile,
        );
        if (added) {
          addedCount++;
        }
        lastChangeId = snapshot.data.syncedChangeIdOrNull ?? lastChangeId;
      }
      if (!complete) {
        break;
      }
      var next = snapshots.last.data.syncedInfoOrNull?.timestamp.v;
      if (next == null || next == lastTimestamp) {
        break;
      }
      lastTimestamp = next;
    }

    if (complete) {
      await _updateMeta(
        (meta) => meta.lastReconcileTimestamp.v = startTimestamp,
      );
    }
    return SyncedFsRebuildResult(
      scannedCount: scannedCount,
      addedCount: addedCount,
      stampedCount: 0,
      lastChangeId: lastChangeId,
      complete: complete,
    );
  }

  /// Walk the whole collection by document id and give a modification number
  /// to every document that has none, appending its change log entry.
  ///
  /// Needed once after enabling the synced helpers on an existing collection,
  /// and for writers bypassing both the collection helper and the trigger.
  /// Documents without a modification number are invisible to [rebuild] and to
  /// [SyncedFsSource.getSnapshot], which both order by it.
  Future<SyncedFsRebuildResult> stampMissingChangeIds({
    int? limit,
    int? stepLimit,
    String? afterDocId,
  }) async {
    var scannedCount = 0;
    var stampedCount = 0;
    var addedCount = 0;
    var complete = true;
    int? lastChangeId;
    var lastDocId = afterDocId;

    while (complete) {
      var query = firestore
          .collection(refs.path)
          .orderById()
          .limit(stepLimit ?? syncedFsDefaultStepLimit);
      if (lastDocId != null) {
        query = query.startAfter(values: [lastDocId]);
      }
      var snapshots = (await query.get()).docs;
      if (snapshots.isEmpty) {
        break;
      }
      for (var snapshot in snapshots) {
        if (limit != null && scannedCount >= limit) {
          complete = false;
          break;
        }
        scannedCount++;
        lastDocId = snapshot.ref.id;
        if (snapshot.data.syncedChangeIdOrNull != null) {
          continue;
        }
        var change = await writer.stampAndAppendChange(
          docId: snapshot.ref.id,
          origin: SyncedFsChangeOrigin.rebuild,
        );
        if (change != null) {
          stampedCount++;
          addedCount++;
          lastChangeId = change.changeId.v;
        }
      }
    }
    return SyncedFsRebuildResult(
      scannedCount: scannedCount,
      addedCount: addedCount,
      stampedCount: stampedCount,
      lastChangeId: lastChangeId,
      complete: complete,
    );
  }

  /// Drop the change log entries strictly before [beforeChangeId] and mark the
  /// collection so that consumers below it do a full resynchronization.
  ///
  /// Returns the number of deleted entries.
  Future<int> truncateChangeLog({required int beforeChangeId}) async {
    var deleted = 0;
    while (true) {
      var list = await refs.changesCollection
          .query()
          .orderBy(changeChangeIdFieldKey)
          .where(changeChangeIdFieldKey, isLessThan: beforeChangeId)
          .limit(syncedFsDefaultStepLimit)
          .get(firestore);
      if (list.isEmpty) {
        break;
      }
      for (var change in list) {
        await firestore.pathDelete(change.path);
        deleted++;
      }
    }
    await _updateMeta((meta) => meta.minIncrementalChangeId.v = beforeChangeId);
    return deleted;
  }

  /// Force every consumer to do a full resynchronization by bumping the source
  /// version. Returns the new version.
  Future<int> bumpVersion() async {
    late int version;
    await _updateMeta((meta) {
      version = (meta.version.v ?? 1) + 1;
      meta.version.v = version;
    });
    return version;
  }

  /// True when the change log entry of [snapshot] was missing and got added.
  Future<bool> _ensureChange(
    DocumentSnapshot snapshot, {
    required String origin,
  }) async {
    var map = snapshot.data;
    var changeId = map.syncedChangeIdOrNull;
    if (changeId == null) {
      /// Not ordered by change id, cannot happen with [source.scanCollection].
      return await writer.stampAndAppendChange(
            docId: snapshot.ref.id,
            origin: origin,
          ) !=
          null;
    }
    var change = await writer.appendChange(
      changeId: changeId,
      docId: snapshot.ref.id,
      deleted: map.syncedIsDeleted,
      data: map,
      updateTime: snapshot.updateTime,
      origin: origin,
    );
    return change != null;
  }

  Future<void> _updateMeta(
    void Function(SyncedFsMetaInfoRecord meta) action,
  ) async {
    await firestore.cvRunTransaction((txn) async {
      var meta = await txn.refGet(refs.metaInfoDocRef);
      action(meta);
      txn.refSet(refs.metaInfoDocRef, meta, SetOptions(merge: true));
    });
  }

  @override
  String toString() => 'SyncedFsChangeLogRebuilder(${refs.path})';
}
