import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
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

final dbSyncRecordModel = SdbSyncRecord();

final sdbSyncMetaStoreRef = scvStringStoreFactory.store<SdbSyncMetaInfo>(
  'syncMeta',
);

final sdbSyncRecordStoreRef = scvIntStoreFactory.store<SdbSyncRecord>(
  'syncRecord',
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
  final syncTimestamp = cvEncodedTimestampField(syncTimestampKey);

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
