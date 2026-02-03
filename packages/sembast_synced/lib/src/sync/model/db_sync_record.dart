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

abstract class DbSyncRecordCommon implements CvModel {
  /// Local store
  CvField<String> get store;

  /// Local key
  CvField<String> get key;

  /// Whether the record is deleted
  bool get isDeleted;

  /// Local dirty/deleted/added
  /// Whether the record is dirty
  bool get isDirty;

  /// Source id
  CvField<String> get syncId;

  /// Source timestamp
  CvField<Timestamp> get syncTimestamp;

  /// Source change id
  CvField<int> get syncChangeId;
}

class DbSyncRecord extends DbIntRecordBase implements DbSyncRecordCommon {
  /// Local store
  @override
  final store = CvField<String>(recordStoreFieldKey);

  /// Local key
  @override
  final key = CvField<String>(recordKeyFieldKey);

  /// Local key

  final deleted = CvField<bool>(recordDeletedFieldKey);

  /// Local dirty/deleted/added
  final dirty = CvField<bool>(recordDirtyFieldKey);

  /// Source id
  @override
  final syncId = CvField<String>(syncIdKey);

  /// Source timestamp
  @override
  final syncTimestamp = CvField<Timestamp>(syncTimestampKey);

  /// Source change id
  @override
  final syncChangeId = CvField<int>(syncChangeIdKey);

  /// The synced key
  SyncedRecordKey get syncedKey =>
      SyncedRecordKey(store: store.v!, key: key.v!);

  /// helper
  RecordRef<String, Map<String, Object?>> get dataRecordRef =>
      stringMapStoreFactory.store(store.v).record(key.v!);

  @override
  List<CvField> get fields => [
    store,
    key,
    deleted,
    dirty,
    syncId,
    syncTimestamp,
    syncChangeId,
  ];

  @override
  bool get isDeleted => deleted.v == true;

  @override
  bool get isDirty => dirty.v == true;
}

DbSyncRecord? dbSyncRecordFromSnapshot(
  RecordSnapshot<int, Map<String, Object?>>? snapshot,
) => snapshot == null
    ? null
    : (DbSyncRecord()
        ..id = snapshot.key
        ..fromMap(snapshot.value));
