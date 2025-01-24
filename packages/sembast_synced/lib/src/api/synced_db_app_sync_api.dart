import 'package:tekaly_sembast_synced/src/api/synced_source_api.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';

/// Sync from firestore
class SyncedDbAppSyncApi with SyncedDbAppSyncMixin implements SyncedDbAppSync {
  SyncedDbAppSyncApi(SyncedDb db, this.sourceApi) {
    this.db = db;
  }

  final SyncedSourceApi sourceApi;

  @override
  Future<void> sync() async {
    var sync = SyncedDbSynchronizer(db: db, source: sourceApi);
    var stat = await sync.sync();
    if (debugSyncedSync) {
      // ignore: avoid_print
      print(stat);
    }
  }
}
