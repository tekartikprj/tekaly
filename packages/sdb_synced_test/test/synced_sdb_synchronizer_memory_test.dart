import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_partition_test.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_synchronizer_test.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

void main() {
  group('synced_db_source_sync_memory_test', () {
    var setupContext = setupNewInMemorySyncSdbTestsContext;

    allSyncedDbTests(setupContext);
    syncedSdbPartitionTests(() async => SyncedSourceMemory().withPartition);
  });
}
