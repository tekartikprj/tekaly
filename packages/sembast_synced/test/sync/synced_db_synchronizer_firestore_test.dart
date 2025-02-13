import 'package:tekaly_sembast_synced/src/sync/synced_db.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

import 'synced_db_synchronizer_test.dart';
import 'synced_source_firestore_test.dart';

void main() {
  group('synced_db_source_sync_firestore_test', () {
    Future<SyncTestsContext> setupContext() async {
      //    setUp(() async {
      return SyncTestsContext()
        ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
        ..source = newInMemorySyncedSourceFirestore();
    }

    //  });
    syncTests(setupContext);
  });
}
