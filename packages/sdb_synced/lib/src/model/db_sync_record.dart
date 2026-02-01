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

final dbSyncMetaStoreRef = scvStringStoreFactory.store<DbSyncMetaInfo>(
  'syncMeta',
);

final dbSyncRecordStoreRef = scvIntStoreFactory.store<SdbSyncRecord>(
  'syncRecord',
);

/// Index to find by syncId
final dbSyncRecordBySyncIndexRef = dbSyncRecordStoreRef.index('bySyncId');

class SdbSyncRecord extends ScvIntRecordBase implements DbSyncRecordCommon {
  /// Local store
  @override
  final store = CvField<String>(recordStoreFieldKey);

  /// Local key
  @override
  final key = CvField<String>(recordKeyFieldKey);

  /// Local key
  @override
  final deleted = CvField<bool>(recordDeletedFieldKey);

  /// Local dirty/deleted/added
  @override
  final dirty = CvField<bool>(recordDirtyFieldKey);

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
