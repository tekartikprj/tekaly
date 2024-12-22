import 'package:tekaly_sembast_synced/src/sync/model/db_sync_meta.dart';
import 'package:tekaly_sembast_synced/src/sync/model/db_sync_record.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:test/test.dart';

class _SyncedDbMock extends SyncedDbBase {
  @override
  CvStoreRef<String, DbSyncMetaInfo> get dbSyncMetaStoreRef =>
      throw UnimplementedError();

  @override
  CvStoreRef<int, DbSyncRecord> get dbSyncRecordStoreRef =>
      throw UnimplementedError();

  @override
  Future<Database> get rawDatabase => throw UnimplementedError();
}

void main() {
  group('synced_db_extends', () {
    test('mock', () async {
      _SyncedDbMock();
    });
  });
}
