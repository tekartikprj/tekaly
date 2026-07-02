import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_io.dart';
import 'package:test/test.dart';

import 'synced_source_export_test.dart';
import 'synced_source_test_common.dart';

final _myStoreRef = SdbStoreRef<String, SdbModel>('my_store');
final _prefsStoreRef = SdbStoreRef<String, SdbModel>('prefs');

final _schema = SdbDatabaseSchema(
  stores: [
    _myStoreRef.schema(),
    _prefsStoreRef.schema(),
    ...syncedSdbMetaSchema.stores,
  ],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);

void main() {
  Future<SyncedSdb> autoSynced(SyncedSdb syncedSdb) async {
    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();
    return syncedSdb;
  }

  Future<SyncedSdb> createBasicDatabase() async {
    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    await _myStoreRef.record('my_key').put(db, {'test': 123});
    return autoSynced(syncedSdb);
  }

  test('exportBasicDatabaseToIo', () async {
    var syncedSdb = await createBasicDatabase();
    var db = await syncedSdb.database;

    var dbMeta = (await syncedSdb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    var dir = join('.local', 'test', 'sdb_export_tekaly');
    await Directory(dir).emptyOrCreate();
    await syncedSdb.exportDatabase(dir: dir);

    var meta = await File(join(dir, 'export_meta.json')).readAsString();
    expect(meta, '{"lastChangeId":1,"lastTimestamp":"$timestamp"}');
    var content = await File(join(dir, 'export.jsonl')).readAsString();
    expect(
      content,
      '{"tekaly_export":1,"version":1}\n'
      '{"lastChangeId":1,"lastTimestamp":"$timestamp"}\n'
      '{"store":"my_store"}\n'
      '["my_key",{"test":123}]\n',
    );
    await syncedSdb.close();
    syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    db = await syncedSdb.database;
    expect(await _myStoreRef.record('my_key').getValue(db), isNull);
    expect((await syncedSdb.getSyncMetaInfo()), isNull);
    await syncedSdb.importDatabaseFromFiles(dir: dir);
    expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 1);
    expect(await _myStoreRef.record('my_key').getValue(db), {'test': 123});
  });

  test('exportDemoDataDatabaseToIo tekaly', () async {
    var source = newInMemorySyncedSourceMemory();
    var syncedSdb = await createSyncedDbWithDemoData(source);
    var db = await syncedSdb.database;
    var dbMeta = (await syncedSdb.getSyncMetaInfo())!;
    var timestamp = dbMeta.lastTimestamp.v!.toIso8601String();
    var dir = join('.local', 'test', 'sdb_demo_export_tekaly');
    await Directory(dir).emptyOrCreate();
    await syncedSdb.exportDatabase(dir: dir);

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
    await syncedSdb.close();
    syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    db = await syncedSdb.database;
    expect(await _myStoreRef.record('item_1').getValue(db), isNull);
    expect((await syncedSdb.getSyncMetaInfo()), isNull);
    await syncedSdb.importDatabaseFromFiles(dir: dir);
    expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 3);
    expect(await _myStoreRef.record('item_1').getValue(db), {'test': 123});
    expect(await _myStoreRef.record('item_2').getValue(db), {
      'ts': SdbTimestamp(1, 2000),
      'blob': SdbBlob.fromList([1, 2, 3]),
    });
    expect(await _prefsStoreRef.record('info').getValue(db), {'name': 'demo'});
  });
}
