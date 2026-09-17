import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

final _myStoreRef = SdbStoreRef<String, SdbModel>('my_store');
final _prefsStoreRef = SdbStoreRef<String, SdbModel>('prefs');

final _demoSchema = SdbDatabaseSchema(
  stores: [
    _myStoreRef.schema(),
    _prefsStoreRef.schema(),
    ...syncedSdbMetaSchema.stores,
  ],
);
SyncedSdbOptions _demoOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _demoSchema),
);

/// Sdb database with demo data, synced to [source].
Future<SyncedSdb> createSyncedSdbWithDemoData(SyncedSource source) async {
  var syncedSdb = SyncedSdb.newInMemory(options: _demoOptions());
  var db = await syncedSdb.database;

  // Create some demo data
  // A list of 2 items, one containing all types (SdbTimestamp, SdbBlob)
  await _myStoreRef.record('item_1').put(db, {'test': 123});
  await _myStoreRef.record('item_2').put(db, {
    'ts': SdbTimestamp(1, 2000),
    'blob': SdbBlob.fromList([1, 2, 3]),
  });
  // Another store with a prefs key 'name': 'demo'
  await _prefsStoreRef.record('info').put(db, {'name': 'demo'});

  var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
  await synchronizer.sync();
  return syncedSdb;
}

void main() {
  /// The tekaly export format must be the same for sdb, sembast and a synced
  /// source.
  test('export/import SyncedSdb to SyncedDb', () async {
    var source = SyncedSourceMemory();
    var syncedSdb = await createSyncedSdbWithDemoData(source);
    var exportInfo = await syncedSdb.exportInMemory();
    expect(exportInfo.data, [
      {'tekaly_export': 1, 'version': 1},
      {
        'lastChangeId': 3,
        'lastTimestamp': '${exportInfo.metaInfo.lastTimestamp.v}',
      },
      {'store': 'my_store'},
      [
        'item_1',
        {'test': 123},
      ],
      [
        'item_2',
        {
          'ts': {r'$timestamp': '1970-01-01T00:00:01.000002Z'},
          'blob': {r'$blob': 'AQID'},
        },
      ],
      {'store': 'prefs'},
      [
        'info',
        {'name': 'demo'},
      ],
    ]);

    await syncedSdb.close();

    var syncedDb = SyncedDb.newInMemory();
    await syncedDb.importFromMemory(exportInfo: exportInfo);

    var exportInfoDb = await syncedDb.exportInMemory();
    expect(exportInfoDb.data, exportInfo.data);
    expect(exportInfoDb.metaInfo.toMap(), exportInfo.metaInfo.toMap());
    expect(exportInfoDb, exportInfo);
    await syncedDb.close();

    var exportInfoSource = await source.exportInMemory();
    expect(exportInfoSource.data, exportInfo.data);
  });
}
