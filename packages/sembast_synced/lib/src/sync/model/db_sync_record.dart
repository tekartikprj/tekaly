// ignore_for_file: public_member_api_docs

import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

export 'package:tekaly_synced_db_common/synced_db_common.dart'
    show
        DbSyncRecordCommon,
        syncTimestampKey,
        syncChangeIdKey,
        recordStoreFieldKey,
        recordKeyFieldKey,
        recordDeletedFieldKey,
        recordValueFieldKey,
        recordDirtyFieldKey,
        recordFieldKey,
        syncIdKey;

final dbSyncRecordModel = DbSyncRecord();

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
  final syncTimestamp = CvField<SyncedDbTimestamp>(syncTimestampKey);

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
