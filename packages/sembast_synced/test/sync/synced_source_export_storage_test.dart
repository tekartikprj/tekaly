import 'package:sembast/sembast.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_sembast_synced/synced_db_storage.dart';
import 'package:tekartik_firebase_storage_fs/storage_fs.dart';
import 'package:test/test.dart';

import 'synced_source_test.dart';

void main() {
  test('exportDatabaseToStorage', () async {
    var syncedDb = SyncedDb.newInMemory();
    var storage = newStorageMemory();
    var rootPath = 'my_test';
    await syncedDb.exportDatabaseToStorage(
      exportContext: SyncedDbStorageExportContext(
        storage: storage,
        rootPath: rootPath,
      ),
    );
    var meta =
        await storage.bucket().file('my_test/export_meta.json').readAsString();
    expect(meta, '{"lastChangeId":0}');
    var content =
        await storage.bucket().file('my_test/export_0.jsonl').readAsString();
    expect(content, '{"sembast_export":1,"version":1}\n');
    var db = await syncedDb.database;
    await stringMapStoreFactory.store('my_store').record('my_key').put(db, {
      'test': 123,
    });

    await syncedDb.exportDatabaseToStorage(
      exportContext: SyncedDbStorageExportContext(
        storage: storage,
        rootPath: rootPath,
      ),
    );
    meta =
        await storage.bucket().file('my_test/export_meta.json').readAsString();
    expect(meta, '{"lastChangeId":0}');
    content =
        await storage.bucket().file('my_test/export_0.jsonl').readAsString();
    expect(
      content,
      '{"sembast_export":1,"version":1}\n'
      '{"store":"my_store"}\n'
      '["my_key",{"test":123}]\n',
    );
  });

  test('synced exportDatabaseToStorage', () async {
    var syncedDb = SyncedDb.newInMemory();
    var storage = newStorageMemory();
    var rootPath = 'my_test';
    var db = await syncedDb.database;
    await stringMapStoreFactory.store('my_store').record('my_key').put(db, {
      'test': 123,
    });

    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    var importExportContext = SyncedDbStorageExportContext(
      storage: storage,
      rootPath: rootPath,
    );
    var result = await syncedDb.exportDatabaseToStorage(
      exportContext: importExportContext,
    );
    expect(result.exportSize, 188);
    var meta =
        await storage.bucket().file('my_test/export_meta.json').readAsString();

    var dbMeta = (await syncedDb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    expect(meta, '{"lastChangeId":1,"lastTimestamp":"$timestamp"}');
    var content =
        await storage.bucket().file('my_test/export_1.jsonl').readAsString();
    expect(
      content,
      '{"sembast_export":1,"version":1}\n'
      '{"store":"my_store"}\n'
      '["my_key",{"test":123}]\n'
      '{"store":"syncMeta"}\n'
      '["info",{"lastChangeId":1,"lastTimestamp":{"@Timestamp":"$timestamp"}}]\n',
    );

    await syncedDb.close();
    syncedDb = SyncedDb.newInMemory();
    db = await syncedDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      isNull,
    );
    expect((await syncedDb.getSyncMetaInfo()), isNull);
    await syncedDb.importDatabaseFromStorage(
      importContext: importExportContext,
    );
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      {'test': 123},
    );
  });
}
