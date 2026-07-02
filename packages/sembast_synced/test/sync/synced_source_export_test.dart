import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

void main() {
  Future<SyncedDb> setupBasicDb() async {
    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    await stringMapStoreFactory.store('my_store').record('my_key').put(db, {
      'test': 123,
    });

    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    return syncedDb;
  }

  test('exportInMemory', () async {
    //debugSyncedSync = devTrue;
    var syncedDb = await setupBasicDb();

    var exportInfo = await syncedDb.exportInMemory();
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

    await syncedDb.close();
    syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      isNull,
    );
    expect((await syncedDb.getSyncMetaInfo()), isNull);
    await syncedDb.importFromMemory(exportInfo: exportInfo);
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      {'test': 123},
    );
    exportInfo = await syncedDb.exportInMemory();
    expect(exportInfo.metaInfo.toMap(), expectedMeta);
    expect(exportInfo.data, expectedData);
  });
  test('exportInMemoryLegacy', () async {
    var syncedDb = await setupBasicDb();

    var exportInfo = await syncedDb.exportInMemoryLegacy();
    var timestamp = exportInfo.metaInfo.lastTimestamp.v!;

    var expectedMeta = {'lastChangeId': 1, 'lastTimestamp': timestamp};

    var expectedData = [
      {'sembast_export': 1, 'version': 1},
      {'store': 'local_sync_meta'},
      [
        'info',
        {
          'lastTimestamp': {'@Timestamp': timestamp},
          'lastChangeId': 1,
        },
      ],
      {'store': 'my_store'},
      [
        'my_key',
        {'test': 123},
      ],
    ];
    expect(exportInfo.metaInfo.toMap(), expectedMeta);
    expect(exportInfo.data, expectedData);

    await syncedDb.close();
    syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      isNull,
    );
    expect((await syncedDb.getSyncMetaInfo()), isNull);
    await syncedDb.importFromMemoryLegacy(exportInfo: exportInfo);
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      {'test': 123},
    );
    exportInfo = await syncedDb.exportInMemoryLegacy();
    expect(exportInfo.metaInfo.toMap(), expectedMeta);
    expect(exportInfo.data, expectedData);
  });
}
