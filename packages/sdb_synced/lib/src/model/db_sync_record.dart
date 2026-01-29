import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'db_sync_meta.dart';
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

final dbSyncMetaStoreRef = scvStringStoreFactory.store<DbSyncMetaInfo>(
  'syncMeta',
);

final dbSyncRecordStoreRef = scvIntStoreFactory.store<DbSyncRecord>(
  'syncRecord',
);

class DbSyncRecord extends ScvIntRecordBase {
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
  final syncTimestamp = cvEncodedTimestampField(syncTimestampKey);

  /// Source change id
  final syncChangeId = CvField<int>(syncChangeIdKey);

  /// The synced key
  SyncedRecordKey get syncedKey =>
      SyncedRecordKey(store: store.v!, key: key.v!);

  /// helper
  SdbRecordRef<String, SdbModel> get rawDataRecordRef =>
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
