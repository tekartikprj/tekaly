import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced/synced_source.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

final _myStoreRef = SdbStoreRef<String, SdbModel>('my_store');

final _schema = SdbDatabaseSchema(
  stores: [_myStoreRef.schema(), ...syncedSdbMetaSchema.stores],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);
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
Future<SyncedSdb> createSyncedDbWithDemoData(SyncedSource source) async {
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
  Future<(SyncedSdb, SyncedSource)> setupBasicDb() async {
    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    await _myStoreRef.record('my_key').put(db, {'test': 123});

    var source = newInMemorySyncedSourceMemory();
    var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
    await synchronizer.sync();
    return (syncedSdb, source);
  }

  test('exportInMemory', () async {
    //syncedSdbDebug = true;
    var (syncedSdb, source) = await setupBasicDb();

    var exportInfo = await syncedSdb.exportInMemory();
    var timestamp = exportInfo.metaInfo.lastTimestamp.v!;
    var expectedMeta = {'lastChangeId': 1, 'lastTimestamp': timestamp};

    var expectedData = [
      {'tekaly_export': 1, 'version': 1},
      {'lastChangeId': 1, 'lastTimestamp': timestamp},
      {'store': 'my_store'},
      [
        'my_key',
        {'test': 123},
      ],
    ];
    expect(exportInfo.metaInfo.toMap(), expectedMeta);
    expect(exportInfo.data, expectedData);

    await syncedSdb.close();
    syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    expect(await _myStoreRef.record('my_key').getValue(db), isNull);
    expect((await syncedSdb.getSyncMetaInfo()), isNull);
    await syncedSdb.importFromMemory(exportInfo: exportInfo);
    expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(await _myStoreRef.record('my_key').getValue(db), {'test': 123});
    exportInfo = await syncedSdb.exportInMemory();
    expect(exportInfo.metaInfo.toMap(), expectedMeta);
    expect(exportInfo.data, expectedData);
  });

  test('export/import SyncedSdb to SyncedDb', () async {
    var source = newInMemorySyncedSourceMemory();
    var syncedSdb = await createSyncedDbWithDemoData(source);
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

    //await source.exrt
  });

  test('export/import to/from JSONL string', () async {
    var (syncedSdb, source) = await setupBasicDb();

    var jsonl = await syncedSdb.exportToJsonlString();

    expect(jsonl, contains('{"tekaly_export":1,"version":1}'));
    expect(jsonl, contains('["my_key",{"test":123}]'));

    await syncedSdb.close();
    syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    expect(await _myStoreRef.record('my_key').getValue(db), isNull);
    expect((await syncedSdb.getSyncMetaInfo()), isNull);

    await syncedSdb.importFromJsonlString(jsonl);
    expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(await _myStoreRef.record('my_key').getValue(db), {'test': 123});

    var newJsonl = await syncedSdb.exportToJsonlString();
    expect(newJsonl, jsonl);
    await syncedSdb.close();
  });
}
