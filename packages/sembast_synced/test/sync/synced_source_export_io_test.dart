import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/synced_db_io.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

void main() {
  test('exportDatabaseToIo', () async {
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
    var dbMeta = (await syncedDb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    var dir = join('.dart_tool', 'sembast_synced', 'test', 'export');
    await Directory(dir).emptyOrCreate();
    await syncedDb.exportDatabase(dir: dir);

    var meta = await File(join(dir, 'export_meta.json')).readAsString();
    expect(meta, '{"lastChangeId":1,"lastTimestamp":"$timestamp"}');
    var content = await File(join(dir, 'export.jsonl')).readAsString();
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
    await syncedDb.importDatabaseFromFiles(dir: dir);
    expect((await syncedDb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      {'test': 123},
    );
  });
}
