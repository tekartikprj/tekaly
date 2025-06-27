import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/src/api/import_common.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore_v2.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' as fb;
//import 'package:tekartik_firebase_firestore/utils/auto_id_generator.dart' as fb;
import 'package:tekartik_firebase_firestore/utils/track_changes_support.dart';

import 'sembast_firestore_converter.dart';

/// Synced source firestore
class SyncedSourceFirestore
    with SyncedSourceDefaultMixin
    implements SyncedSource {
  /// Enforced synchronizer version, if any
  int? _version;

  /// Enforced synchronizer version, if any or version read
  int? get version => _version;

  /// Initial version
  static const int version1 = 1;

  /// Generated firestore key is `store|key` (pipe separated)
  static const int version2 = 2;

  static const dataCollectionId = 'data';
  static const metaCollectionId = 'meta';
  static const metaInfoDocumentId = 'info';
  final fb.Firestore firestore;
  final String? rootPath;
  late fb.CollectionReference dataCollection;
  late fb.CollectionReference metaCollection;
  late fb.DocumentReference metaInfoReference;

  /// True when used without auth during development
  final bool noAuth;

  @override
  Future<void> close() async {}

  SyncedSourceFirestore({
    required this.firestore,

    /// Document path
    @required this.rootPath,
    this.noAuth = false,
  }) {
    initBuilders();

    dataCollection = firestore.collection(getPath(dataCollectionId));
    metaCollection = firestore.collection(getPath(metaCollectionId));
    metaInfoReference = metaCollection.doc(metaInfoDocumentId);
  }

  String getPath(String path) {
    if (rootPath == null) {
      return path;
    } else {
      return url.join(rootPath!, path);
    }
  }

  Model _prepareRecordMap(CvSyncedSourceRecord record) {
    // Clear the id
    record.syncId.clear();
    var map = mapSembastToFirestore(record.toMap());
    // Generate timestamp
    map[syncTimestampKey] = fb.FieldValue.serverTimestamp;
    return asModel(map);
  }

  @override
  @visibleForTesting
  Future<void> putRawRecord(CvSyncedSourceRecord record) async {
    var id = record.syncId.v!;
    record.syncId.clear();
    var map = mapSembastToFirestore(record.toMap());
    try {
      await dataCollection.doc(id).set(map);
    } catch (e) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Error $e while putting record at ${dataCollection.doc(id)}');
      }

      rethrow;
    }
  }

  String _generateSyncId(CvSyncedSourceRecord record) {
    return '${record.recordStore}|${record.recordKey}';
  }

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(
    CvSyncedSourceRecord record,
  ) async {
    fixAndCheckPutSyncedRecord(record);
    var newRecord = false;
    var ref = SyncedDataSourceRef(
      store: record.record.v!.store.v,
      key: record.record.v!.key.v,
      syncId: record.syncId.v,
    );
    var existing = await getSourceRecord(ref);
    if (existing == null) {
      newRecord = true;

      /// Generate sync id
      ref = SyncedDataSourceRef(
        store: record.recordStore,
        key: record.recordKey,
        syncId: _generateSyncId(record),
      );
    } else {
      ref = SyncedDataSourceRef(
        store: ref.store,
        key: ref.key,
        syncId: existing.syncId.v,
      );
    }
    var map = _prepareRecordMap(record);

    // Warning this does not work in non authenticated mode
    // and even rest auth (not service account).
    await firestore.runTransaction((txn) async {
      var meta = await txnGetMetaInfo(txn);

      var existing = await txnGetSourceRecordById(txn, ref.syncId!);
      if (newRecord) {
        if (existing != null) {
          throw StateError(
            'Expect not existing source record ${ref.syncId}, try again',
          );
        }
      } else {
        if (existing == null) {
          throw StateError(
            'Expect existing source record ${ref.syncId}, try again',
          );
        }
      }
      // increment change id
      var lastChangeId = (meta?.lastChangeId.v ?? 0) + 1;

      // Set in map and update meta info
      map[syncChangeIdKey] = lastChangeId;
      txn.set(dataCollection.doc(ref.syncId!), map, fb.SetOptions(merge: true));
      txn.set(metaInfoReference, {
        metaLastChangeIdKey: lastChangeId,
      }, fb.SetOptions(merge: true));
    });

    return (await getSourceRecord(ref))!;
  }

  @override
  Future<CvMetaInfo?> getMetaInfo() async =>
      getRecord<CvMetaInfo>(metaInfoReference);

  Future<CvMetaInfo?> txnGetMetaInfo(fb.Transaction txn) async =>
      _txnGetRecord<CvMetaInfo>(txn, metaInfoReference);

  @override
  Future<CvMetaInfo> putMetaInfo(CvMetaInfo info) async {
    await firestore.runTransaction((txn) async {
      var existing = await _txnGetRecord<CvMetaInfo>(txn, metaInfoReference);
      // timestamp can only be later
      if (existing?.minIncrementalChangeId.v != null) {
        if (info.minIncrementalChangeId.v != null) {
          if (info.minIncrementalChangeId.v!.compareTo(
                existing!.minIncrementalChangeId.v!,
              ) <
              0) {
            throw StateError(
              'minIncrementTimestamp ${info.minIncrementalChangeId.v} cannot be less then existing ${existing.minIncrementalChangeId.v}',
            );
          }
        }
      }
      _txnSetRecord(txn, metaInfoReference, info, merge: true);
    });
    return (await getMetaInfo())!;
  }

  Future<T?> getRecord<T extends CvModel>(fb.DocumentReference doc) async {
    return cvRecordFromSnapshot<T>(await doc.get());
  }

  Future<T?> _txnGetRecord<T extends CvModel>(
    fb.Transaction txn,
    fb.DocumentReference doc,
  ) async {
    return cvRecordFromSnapshot<T>(await txn.get(doc));
  }

  void _txnSetRecord(
    fb.Transaction txn,
    fb.DocumentReference doc,
    CvModel record, {
    bool? merge,
  }) async {
    txn.set(
      doc,
      mapSembastToFirestore(record.toMap()),
      fb.SetOptions(merge: merge ?? false),
    );
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(
    SyncedDataSourceRef sourceRef,
  ) async {
    /// Try by sync id first
    if (sourceRef.syncId != null) {
      var doc = dataCollection.doc(sourceRef.syncId!);
      var raw = await doc.get();
      if (raw.exists) {
        var record = sourceRecordFromSnapshot(raw)!;
        if (record.recordStore == sourceRef.store &&
            record.recordKey == sourceRef.key) {
          return record;
        }

        if (debugSyncedSync) {
          // ignore: avoid_print
          print('getSourceRecord Invalid record $record for ref $sourceRef');
        }
      }
    }
    var querySnapshot = await dataCollection
        .where(
          '$recordFieldKey.$recordStoreFieldKey',
          isEqualTo: sourceRef.store,
        )
        .where('$recordFieldKey.$recordKeyFieldKey', isEqualTo: sourceRef.key)
        .limit(1)
        .get();
    if (querySnapshot.docs.isNotEmpty) {
      return sourceRecordFromSnapshot(querySnapshot.docs.first);
    }
    return null;
  }

  Future<CvSyncedSourceRecord?> txnGetSourceRecordById(
    fb.Transaction txn,
    String syncId,
  ) async {
    var doc = dataCollection.doc(syncId);
    var raw = await txn.get(doc);
    return sourceRecordFromSnapshot(raw);
  }

  Future<CvSyncedSourceRecord?> getSourceRecordById(
    fb.Transaction txn,
    String syncId,
  ) async {
    return sourceRecordFromSnapshot(await dataCollection.doc(syncId).get());
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) async {
    includeDeleted ??= false;
    var query = dataCollection.orderBy(syncChangeIdKey);
    // devPrint('dataCollaction $dataCollection');
    // devPrint('rootPath $rootPath');
    if (afterChangeId != null) {
      query = query.startAfter(values: [afterChangeId]);
    }
    if (limit != null) {
      query = query.limit(limit);
    }
    fb.QuerySnapshot querySnapshot;
    try {
      querySnapshot = await query.get();
    } catch (e) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Error $e while getting record list at $query');
      }
      rethrow;
    }
    /*
    return sourceRecordFromSnapshots(querySnapshot.docs)
        .cast<SyncedSourceRecord>();

     */

    var unfilteredList = querySnapshot.docs
        .map(
          (snapshot) =>
              snapshot.data.fromFirestore().cv<CvSyncedSourceRecord>()
                ..syncId.v = snapshot.ref.id,
        )
        .toList();
    var list = unfilteredList
        .where(
          (element) => (includeDeleted ?? false) ? true : !element.isDeleted,
        )
        .toList();
    var lastChangeNum = unfilteredList.lastOrNull?.syncChangeId.v;
    return SyncedSourceRecordList(list, lastChangeNum);
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) {
    return metaInfoReference
        .onSnapshotSupport(
          options: TrackChangesPullOptions(
            refreshDelay: checkDelay ?? const Duration(minutes: 60),
          ),
        )
        .map((snapshot) {
          if (snapshot.exists) {
            return cvRecordFromSnapshot<CvMetaInfo>(snapshot);
          }
          return null;
        });
  }
}
