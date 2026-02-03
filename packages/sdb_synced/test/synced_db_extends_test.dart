import 'package:idb_shim/sdb.dart';
import 'package:tekaly_sdb_synced/src/model/db_sync_meta.dart';
import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb.dart';
import 'package:tekartik_app_cv_sdb/src/scv_store_ref.dart';
import 'package:test/test.dart';

class _SyncedDbMock extends SyncedSdbBase {
  _SyncedDbMock({required super.options});

  /*
  @override
  CvStoreRef<String, DbSyncMetaInfo> get dbSyncMetaStoreRef =>
      throw UnimplementedError();

  @override
  CvStoreRef<int, DbSyncRecord> get dbSyncRecordStoreRef =>
      throw UnimplementedError();
*/
  @override
  Future<SdbDatabase> get rawDatabase => throw UnimplementedError();

  @override
  // TODO: implement dbSyncMetaStoreRef
  ScvStoreRef<String, SdbSyncMetaInfo> get dbSyncMetaStoreRef =>
      throw UnimplementedError();

  @override
  // TODO: implement dbSyncRecordStoreRef
  ScvStoreRef<int, SdbSyncRecord> get dbSyncRecordStoreRef =>
      throw UnimplementedError();
}

void main() {
  group('synced_db_extends', () {
    test('mock', () async {
      _SyncedDbMock(
        options: SyncedSdbOptions(
          version: 1,
          schema: SdbDatabaseSchema(stores: []),
        ),
      );
    });
  });
}
