import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_synchronizer_test.dart';

import 'synced_db_read_min_service_test.dart';
export 'package:tekaly_sembast_synced_test/synced_source_test.dart';

/// Entity in the database.
class DbEntity extends ScvStringRecordBase {
  final name = CvField<String>('name');
  final timestamp = CvField<SdbTimestamp>('timestamp');

  @override
  List<CvField> get fields => [name, timestamp];
}

var sdbEntityStoreRef = scvStringStoreFactory.store<DbEntity>('entity');
String get dbEntityStoreName => sdbEntityStoreRef.name;

/// Database schema (synced)
var sdbEntitySchema = SdbDatabaseSchema(
  stores: [sdbEntityStoreRef.schema(), ...syncedSdbMetaSchema.stores],
);
var syncedStoreNames = [dbEntityStoreName];
var sdbEntityOptions = SyncedSdbOptions(
  version: 1,
  schema: sdbEntitySchema,
  syncedStoreNames: syncedStoreNames,
);

void allSyncedDbTests(Future<SyncSdbTestsContext> Function() setupContext) {
  syncTests(setupContext);
  syncedDbReadMinServiceTests(setupContext);
}
