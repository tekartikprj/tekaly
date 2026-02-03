import 'package:tekaly_sdb_synced/sdb_synced.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_synchronizer_test.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:tekaly_sembast_synced_test/synced_source_firestore_test.dart';

// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

void main() {
  group('synced_db_source_sync_firestore_test', () {
    Future<SyncSdbTestsContext> setupContext() async {
      return SyncSdbTestsContext()
        ..syncedSdb = SyncedSdb.newInMemory(options: dbEntityOptions)
        ..source = newInMemorySyncedSourceFirestore();
    }

    allSyncedDbTests(setupContext);
  });
}
