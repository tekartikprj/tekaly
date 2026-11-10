import 'package:tekaly_sembast_synced/src/api/secure_client.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source_api.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase_sim.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db.dart';
import 'package:tekaly_sembast_synced_test/synced_db_synchronizer_test.dart';
import 'package:tekaly_sembast_synced_test/synced_source_test.dart';
import 'package:sembast/sembast_memory.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

/// A new api source on a new in memory server.
Future<SyncedSourceApi> newSyncedSourceApi() async {
  firebaseSimContext = initFirebaseSimMemory();
  var apiService = SecureApiServiceBase(
    packageName: 'test.package',
    isLocal: true,
    app: 'test_app',
    appType: 'test_type',
    functionName: 'test_fn',
    sembastDatabaseFactory: newDatabaseFactoryMemory(),
  );

  await apiService.initClient();

  return SyncedSourceApi(apiService: apiService, target: 'test');
}

void main() {
  // debugWebServices = devWarning(true);

  group('synced_db_source_sync_api_test', () {
    Future<SyncTestsContext> setupContext() async {
      return SyncTestsContext()
        ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
        ..source = await newSyncedSourceApi();
    }

    syncTests(setupContext);
  });
  group('synced_source_api_common_test', () {
    // No real time meta info; no data in the api means deleted.
    runSyncedSourceTest(
      newSyncedSourceApi,
      skipRealTimeChanges: true,
      skipRecordWithoutValue: true,
    );
  });
}
