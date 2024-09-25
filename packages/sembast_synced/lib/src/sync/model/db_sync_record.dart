import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

import 'source_record.dart';

const syncTimestampKey = 'syncTimestamp';
const syncChangeIdKey = 'syncChangeId';
const recordStoreFieldKey = 'store';
const recordKeyFieldKey = 'key';
const recordDeletedFieldKey = 'deleted';
const recordValueFieldKey = 'value';
const recordDirtyFieldKey = 'dirty';
const recordFieldKey = 'record';
const syncIdKey = 'syncId';

final dbSyncRecordModel = DbSyncRecord();

class DbSyncRecord extends DbIntRecordBase {
  /// Local store
  final store = CvField<String>(recordStoreFieldKey);

  /// Local key
  final key = CvField<String>(recordKeyFieldKey);

  /// Local key
  final deleted = CvField<bool>(recordDeletedFieldKey);

  /// Local dirty/deleted/added
  final dirty = CvField<bool>(recordDirtyFieldKey);

  /// Source id
  final syncId = CvField<String>(syncIdKey);

  /// Source timestamp
  final syncTimestamp = CvField<Timestamp>(syncTimestampKey);

  /// Source change id
  final syncChangeId = CvField<int>(syncChangeIdKey);

  /// The synced key
  SyncedRecordKey get syncedKey =>
      SyncedRecordKey(store: store.v!, key: key.v!);

  /// helper
  RecordRef<String, Map<String, Object?>> get dataRecordRef =>
      stringMapStoreFactory.store(store.v).record(key.v!);

  @override
  List<CvField> get fields =>
      [store, key, deleted, dirty, syncId, syncTimestamp, syncChangeId];
}

DbSyncRecord? dbSyncRecordFromSnapshot(
        RecordSnapshot<int, Map<String, Object?>>? snapshot) =>
    snapshot == null
        ? null
        : (DbSyncRecord()
          ..id = snapshot.key
          ..fromMap(snapshot.value));
