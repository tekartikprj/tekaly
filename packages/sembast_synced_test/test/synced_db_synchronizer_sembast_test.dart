import 'package:tekaly_sembast_synced/synced_db_sembast.dart';
import 'package:tekaly_sembast_synced_test/synced_db_read_min_service_test.dart';
import 'package:tekaly_sembast_synced_test/synced_db_synchronizer_test.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

void main() {
  group('synced_db_source_sync_sembast_test', () {
    Future<SyncTestsContext> setupContext() async {
      //    setUp(() async {
      return SyncTestsContext()
        ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
        ..source = await newInMemorySyncedSourceSembast();
    }

    //  });
    syncTests(setupContext);
    syncedDbReadMinServiceTests(setupContext);
  });
}
