import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:sembast/blob.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/synced_db_io.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

void main() {
  Future<SyncedDb> autoSynced(SyncedDb syncedDb) async {
    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    return syncedDb;
  }

  Future<SyncedDb> createBasicDatabase() async {
    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    await stringMapStoreFactory.store('my_store').record('my_key').put(db, {
      'test': 123,
    });
    return autoSynced(syncedDb);

    // Create some demo data
  }

  test('exportBasicDatabaseToIo', () async {
    var syncedDb = await createBasicDatabase();
    var db = await syncedDb.database;

    var dbMeta = (await syncedDb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    var dir = join('.local', 'test', 'export_legacy');
    await Directory(dir).emptyOrCreate();
    await syncedDb.exportDatabaseLegacy(dir: dir);

    var meta = await File(join(dir, 'export_meta.json')).readAsString();
    expect(meta, '{"lastChangeId":1,"lastTimestamp":"$timestamp"}');
    var content = await File(join(dir, 'export.jsonl')).readAsString();
    expect(
      content,
      '{"sembast_export":1,"version":1}\n'
      '{"store":"local_sync_meta"}\n'
      '["info",{"lastChangeId":1,"lastTimestamp":{"@Timestamp":"$timestamp"}}]\n'
      '{"store":"my_store"}\n'
      '["my_key",{"test":123}]\n',
    );
    await syncedDb.close();
    syncedDb = SyncedDb.newInMemory();
    db = await syncedDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      isNull,
    );
    expect((await syncedDb.getSyncMetaInfo()), isNull);
    await syncedDb.importDatabaseFromFilesLegacy(dir: dir);
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      {'test': 123},
    );
  });
  Future<SyncedDb> createSyncedDbWithDemoData() async {
    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;

    // Create some demo data
    // A list of 2 item, one containing all types (DbTimestamp, DbBlob)
    await stringMapStoreFactory.store('my_store').record('item_1').put(db, {
      'test': 123,
    });
    await stringMapStoreFactory.store('my_store').record('item_2').put(db, {
      'ts': Timestamp(1, 2000),
      'blob': Blob.fromList([1, 2, 3]),
    });
    // Another store with a prefs key 'name': 'demo'
    await stringMapStoreFactory.store('prefs').record('info').put(db, {
      'name': 'demo',
    });

    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    return syncedDb;
  }

  test('exportDemoDataDatabaseToIo legacy', () async {
    var syncedDb = await createSyncedDbWithDemoData();
    var db = await syncedDb.database;
    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    var dbMeta = (await syncedDb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    var dir = join('.local', 'test', 'demo_export_legacy');
    await Directory(dir).emptyOrCreate();
    await syncedDb.exportDatabaseLegacy(dir: dir);

    var meta = await File(join(dir, 'export_meta.json')).readAsString();
    expect(meta, '{"lastChangeId":3,"lastTimestamp":"$timestamp"}');
    var content = await File(join(dir, 'export.jsonl')).readAsString();
    var expectedData =
        '{"sembast_export":1,"version":1}\n'
        '{"store":"local_sync_meta"}\n'
        '["info",{"lastChangeId":3,"lastTimestamp":{"@Timestamp":"$timestamp"}}]\n'
        '{"store":"my_store"}\n'
        '["item_1",{"test":123}]\n'
        '["item_2",{"blob":{"@Blob":"AQID"},"ts":{"@Timestamp":"1970-01-01T00:00:01.000002Z"}}]\n'
        '{"store":"prefs"}\n'
        '["info",{"name":"demo"}]\n';
    expect(content, expectedData);
    await syncedDb.close();
    syncedDb = SyncedDb.newInMemory();
    db = await syncedDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('item_1').get(db),
      isNull,
    );
    expect((await syncedDb.getSyncMetaInfo()), isNull);
    await syncedDb.importDatabaseFromFilesLegacy(dir: dir);
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 3);
    expect(
      await stringMapStoreFactory.store('my_store').record('item_1').get(db),
      {'test': 123},
    );
    expect(
      await stringMapStoreFactory.store('my_store').record('item_2').get(db),
      {
        'ts': SyncedDbTimestamp(1, 2000),
        'blob': SyncedDbBlob.fromList([1, 2, 3]),
      },
    );
    expect(await stringMapStoreFactory.store('prefs').record('info').get(db), {
      'name': 'demo',
    });
  });

  test('exportDemoDataDatabaseToIo tekaly', () async {
    // debugSyncedSync = devTrue;
    var syncedDb = await createSyncedDbWithDemoData();
    var db = await syncedDb.database;
    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    var dbMeta = (await syncedDb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    var dir = join('.local', 'test', 'demo_export_tekaly');
    await Directory(dir).emptyOrCreate();
    await syncedDb.exportDatabaseTekaly(dir: dir);

    var meta = await File(join(dir, 'export_meta.json')).readAsString();
    expect(meta, '{"lastChangeId":3,"lastTimestamp":"$timestamp"}');
    var content = await File(join(dir, 'export.jsonl')).readAsString();
    var expectedData =
        '{"tekaly_export":1,"version":1}\n'
        '{"lastChangeId":3,"lastTimestamp":"$timestamp"}\n'
        '{"store":"my_store"}\n'
        '["item_1",{"test":123}]\n'
        r'["item_2",{"blob":{"$blob":"AQID"},"ts":{"$timestamp":"1970-01-01T00:00:01.000002Z"}}]'
        '\n'
        '{"store":"prefs"}\n'
        '["info",{"name":"demo"}]\n';
    expect(content, expectedData);
    await syncedDb.close();
    syncedDb = SyncedDb.newInMemory();
    db = await syncedDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('item_1').get(db),
      isNull,
    );
    expect((await syncedDb.getSyncMetaInfo()), isNull);
    await syncedDb.importDatabaseFromFiles(dir: dir);
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 3);
    expect(
      await stringMapStoreFactory.store('my_store').record('item_1').get(db),
      {'test': 123},
    );
    expect(
      await stringMapStoreFactory.store('my_store').record('item_2').get(db),
      {
        'ts': SyncedDbTimestamp(1, 2000),
        'blob': SyncedDbBlob.fromList([1, 2, 3]),
      },
    );
    expect(await stringMapStoreFactory.store('prefs').record('info').get(db), {
      'name': 'demo',
    });
  });
}
