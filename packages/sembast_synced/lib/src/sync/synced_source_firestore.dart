import 'package:path/path.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore_v2.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' as fb;
import 'package:tekartik_firebase_firestore/utils/auto_id_generator.dart' as fb;
import 'package:tekartik_firebase_firestore/utils/track_changes_support.dart';

import 'model/db_sync_record.dart';
import 'model/source_meta_info.dart';
import 'model/source_record.dart';
import 'sembast_firestore_converter.dart';
import 'synced_source.dart';

class SyncedSourceFirestore
    with SyncedSourceDefaultMixin
    implements SyncedSource {
  final fb.Firestore firestore;
  final String? rootPath;
  late fb.CollectionReference dataCollection;
  late fb.CollectionReference metaCollection;
  late fb.DocumentReference metaInfoReference;

  /// True when used without auth during development
  final bool noAuth;

  @override
  void close() {
    // Nothing to close
  }
  SyncedSourceFirestore(
      {required this.firestore,

      /// Document path
      @required this.rootPath,
      this.noAuth = false}) {
    dataCollection = firestore.collection(getPath('data'));
    metaCollection = firestore.collection(getPath('meta'));
    metaInfoReference = metaCollection.doc('info');

    cvFirestoreAddBuilder<SyncedSourceRecord>((_) => SyncedSourceRecord());
    cvFirestoreAddBuilder<CvMetaInfoRecord>((_) => CvMetaInfoRecord());
  }

  String getPath(String path) {
    if (rootPath == null) {
      return path;
    } else {
      return url.join(rootPath!, path);
    }
  }

  Model _prepareRecordMap(SyncedSourceRecord record) {
    // Clear the id
    record.syncId.clear();
    var map = mapSembastToFirestore(record.toMap());
    // Generate timestamp
    map[syncTimestampKey] = fb.FieldValue.serverTimestamp;
    return asModel(map);
  }

  @override
  @visibleForTesting
  Future<void> putRawRecord(SyncedSourceRecord record) async {
    var id = record.syncId.v!;
    record.syncId.clear();
    var map = mapSembastToFirestore(record.toMap());
    try {
      await dataCollection.doc(id).set(map);
    } catch (e) {
      print('Error $e while putting record at ${dataCollection.doc(id)}');
      rethrow;
    }
  }

  @override
  Future<SyncedSourceRecord?> putSourceRecord(SyncedSourceRecord record) async {
    fixAndCheckPutSyncedRecord(record);
    var newRecord = false;
    var ref = SyncedDataSourceRef(
        store: record.record.v!.store.v,
        key: record.record.v!.key.v,
        syncId: record.syncId.v);
    var existing = await getSourceRecord(ref);
    if (existing == null) {
      newRecord = true;

      /// Generate sync id
      ref = SyncedDataSourceRef(
          store: record.recordStore,
          key: record.recordKey,
          syncId: fb.AutoIdGenerator.autoId());
    } else {
      ref = SyncedDataSourceRef(
          store: ref.store, key: ref.key, syncId: existing.syncId.v);
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
              'Expect not existing source record ${ref.syncId}, try again');
        }
      } else {
        if (existing == null) {
          throw StateError(
              'Expect existing source record ${ref.syncId}, try again');
        }
      }
      // increment change id
      var lastChangeId = (meta?.lastChangeId.v ?? 0) + 1;

      // Set in map and update meta info
      map[syncChangeIdKey] = lastChangeId;
      txn.set(dataCollection.doc(ref.syncId!), map, fb.SetOptions(merge: true));
      txn.set(metaInfoReference, {metaLastChangeIdKey: lastChangeId},
          fb.SetOptions(merge: true));
    });

    return getSourceRecord(ref);
  }

  @override
  Future<CvMetaInfoRecord?> getMetaInfo() async =>
      getRecord<CvMetaInfoRecord>(metaInfoReference);

  Future<CvMetaInfoRecord?> txnGetMetaInfo(fb.Transaction txn) async =>
      _txnGetRecord<CvMetaInfoRecord>(txn, metaInfoReference);

  @override
  Future<CvMetaInfoRecord?> putMetaInfo(CvMetaInfoRecord info) async {
    await firestore.runTransaction((txn) async {
      var existing =
          await _txnGetRecord<CvMetaInfoRecord>(txn, metaInfoReference);
      // timestamp can only be later
      if (existing?.minIncrementalChangeId.v != null) {
        if (info.minIncrementalChangeId.v != null) {
          if (info.minIncrementalChangeId.v!
                  .compareTo(existing!.minIncrementalChangeId.v!) <
              0) {
            throw StateError(
                'minIncrementTimestamp ${info.minIncrementalChangeId.v} cannot be less then existing ${existing.minIncrementalChangeId.v}');
          }
        }
      }
      _txnSetRecord(txn, metaInfoReference, info, merge: true);
    });
    return getMetaInfo();
  }

  Future<T?> getRecord<T extends CvModel>(fb.DocumentReference doc) async {
    return cvRecordFromSnapshot<T>(await doc.get());
  }

  Future<T?> _txnGetRecord<T extends CvModel>(
      fb.Transaction txn, fb.DocumentReference doc) async {
    return cvRecordFromSnapshot<T>(await txn.get(doc));
  }

  void _txnSetRecord(
      fb.Transaction txn, fb.DocumentReference doc, CvModel record,
      {bool? merge}) async {
    txn.set(doc, mapSembastToFirestore(record.toMap()),
        fb.SetOptions(merge: merge ?? false));
  }

  @override
  Future<SyncedSourceRecord?> getSourceRecord(
      SyncedDataSourceRef sourceRef) async {
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
        print('getSourceRecord Invalid record $record for ref $sourceRef');
      }
    }
    var querySnapshot = await dataCollection
        .where('$recordFieldKey.$recordStoreFieldKey',
            isEqualTo: sourceRef.store)
        .where('$recordFieldKey.$recordKeyFieldKey', isEqualTo: sourceRef.key)
        .limit(1)
        .get();
    if (querySnapshot.docs.isNotEmpty) {
      return sourceRecordFromSnapshot(querySnapshot.docs.first);
    }
    return null;
  }

  Future<SyncedSourceRecord?> txnGetSourceRecordById(
      fb.Transaction txn, String syncId) async {
    var doc = dataCollection.doc(syncId);
    var raw = await txn.get(doc);
    return sourceRecordFromSnapshot(raw);
  }

  Future<SyncedSourceRecord?> getSourceRecordById(
      fb.Transaction txn, String syncId) async {
    return sourceRecordFromSnapshot(await dataCollection.doc(syncId).get());
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList(
      {int? afterChangeId, int? limit, bool? includeDeleted}) async {
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
      print('Error $e while getting record list at $query');
      rethrow;
    }
    /*
    return sourceRecordFromSnapshots(querySnapshot.docs)
        .cast<SyncedSourceRecord>();

     */

    var unfilteredList = querySnapshot.docs
        .map((snapshot) =>
            snapshot.data.fromFirestore().cv<SyncedSourceRecord>()
              ..syncId.v = snapshot.ref.id)
        .toList();
    var list = unfilteredList
        .where(
            (element) => (includeDeleted ?? false) ? true : !element.isDeleted)
        .toList();
    var lastChangeNum = unfilteredList.lastOrNull?.syncChangeId.v;
    return SyncedSourceRecordList(list, lastChangeNum);
  }

  @override
  Stream<CvMetaInfoRecord?> onMetaInfo({Duration? checkDelay}) {
    return metaInfoReference
        .onSnapshotSupport(
            options: TrackChangesPullOptions(
                refreshDelay: checkDelay ?? Duration(minutes: 60)))
        .map((snapshot) {
      if (snapshot.exists) {
        return cvRecordFromSnapshot<CvMetaInfoRecord>(snapshot);
      }
      return null;
    });
  }
}
