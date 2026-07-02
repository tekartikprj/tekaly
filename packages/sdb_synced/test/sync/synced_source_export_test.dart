import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

final _myStoreRef = SdbStoreRef<String, SdbModel>('my_store');

final _schema = SdbDatabaseSchema(
  stores: [_myStoreRef.schema(), ...syncedSdbMetaSchema.stores],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);

void main() {
  Future<SyncedSdb> setupBasicDb() async {
    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    await _myStoreRef.record('my_key').put(db, {'test': 123});

    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    return syncedSdb;
  }

  test('exportInMemory', () async {
    //syncedSdbDebug = true;
    var syncedSdb = await setupBasicDb();

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
}
