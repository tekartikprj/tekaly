import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'source_record.dart';

/// Sync timestamp key.
const syncTimestampKey = 'syncTimestamp';

/// Sync change id key.
const syncChangeIdKey = 'syncChangeId';

/// Record store field key.
const recordStoreFieldKey = 'store';

/// Record key field key.
const recordKeyFieldKey = 'key';

/// Record deleted field key.
const recordDeletedFieldKey = 'deleted';

/// Record value field key.
const recordValueFieldKey = 'value';

/// Record dirty field key.
const recordDirtyFieldKey = 'dirty';

/// Record field key.
const recordFieldKey = 'record';

/// Sync id key.
const syncIdKey = 'syncId';

/// Sync record model.
final dbSyncRecordModel = SdbSyncRecord();

/// Sync meta store.
final sdbSyncMetaStoreRef = scvStringStoreFactory.store<SdbSyncMetaInfo>(
  'local_sync_meta',
);

/// Sync record store.
final sdbSyncRecordStoreRef = scvIntStoreFactory.store<SdbSyncRecord>(
  'local_sync_record',
);

/// Index to find by syncId
final sdbSyncRecordBySyncIndexRef = sdbSyncRecordStoreRef.index<String>(
  'bySyncId',
);

/// Index to find dirty records
final sdbSyncRecordDirtyIndexRef = sdbSyncRecordStoreRef.index<int>('dirty');

/// Index to find by store and key
final sdbSyncRecordByStoreAndKeyIndexRef = sdbSyncRecordStoreRef
    .index2<String, String>('byStoreAndKey');

/// Sdb sync record.
class SdbSyncRecord extends ScvIntRecordBase implements DbSyncRecordCommon {
  /// Local store
  @override
  final store = CvField<String>(recordStoreFieldKey);

  /// Local key
  @override
  final key = CvField<String>(recordKeyFieldKey);

  /// Whether the record is deleted
  @override
  bool get isDeleted => deleted.v == 1;

  /// Local key
  final deleted = CvField<int>(recordDeletedFieldKey);

  /// Whether the record is dirty
  @override
  bool get isDirty => dirty.v == 1;

  /// Local dirty/deleted/added
  final dirty = CvField<int>(recordDirtyFieldKey);

  /// Source id
  @override
  final syncId = CvField<String>(syncIdKey);

  /// Source timestamp
  @override
  final syncTimestamp = CvField<SdbTimestamp>(syncTimestampKey);

  /// Source change id
  @override
  final syncChangeId = CvField<int>(syncChangeIdKey);

  /// The synced key
  SyncedRecordKey get syncedKey =>
      SyncedRecordKey(store: store.v!, key: key.v!);

  /// helper
  SdbRecordRef<String, SdbModel> get dataRecordRef =>
      SdbStoreRef<String, SdbModel>(store.v!).record(key.v!);

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
}
