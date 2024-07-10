import 'package:tekaly_sembast_synced/src/api/secure_client.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source_api.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase_sim.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

import 'sync/synced_db_source_sync_test.dart';

void main() {
  // debugWebServices = devWarning(true);

  group('synced_db_source_sync_api_test', () {
    Future<SyncTestsContext> setupContext() async {
//    setUp(() async {
      firebaseSimContext = initFirebaseSimMemory();
      var apiService = SecureApiServiceBase(
        packageName: 'test.package',
        isLocal: true,
        app: 'test_app',
        appType: 'test_type',
        functionName: 'test_fn',
      );

      await apiService.initClient();

      var sourcedSource =
          SyncedSourceApi(apiService: apiService, target: 'test');

      return SyncTestsContext()
        ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
        ..source = sourcedSource;
    }

    //  });
    syncTests(setupContext);
  });
}
