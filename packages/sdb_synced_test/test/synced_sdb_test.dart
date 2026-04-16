// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:dev_test/test.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';

void main() {
  cvAddConstructor(DbEntity.new);
  group('synced_db', () {
    late SyncedSdb syncedDb;
    setUp(() async {
      syncedDb = SyncedSdb.newInMemory(options: sdbEntityAndLocalOptions);
    });
    tearDown(() async {
      await syncedDb.close();
    });
    test('stores', () async {
      expect(syncedDb.scvSyncMetaStoreRef.name, 'local_sync_meta');
      expect(syncedDb.scvSyncRecordStoreRef.name, 'local_sync_record');
      await syncedDb.database;
      expect(syncedDb.syncedStoreNames, ['entity']);
    });
    test('add unsynced record', () async {
      var db = await syncedDb.database;
      await sdbLocalEntityStoreRef.add(db, DbEntity()..name.v = 'test');
      expect(await syncedDb.getSyncRecords(), isEmpty);
    });
    test('add/delete record', () async {
      var db = await syncedDb.database;
      var key = (await sdbEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1,
      ]);
      await sdbEntityStoreRef.record(key).delete(db);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1
          ..deleted.v = 1,
      ]);
    });

    test('add/put/delete record', () async {
      var db = await syncedDb.database;
      var key = (await sdbEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      var ref = sdbEntityStoreRef.record(key);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1,
      ]);
      await (ref.cv()..name.v = 'updated').put(db);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1,
      ]);
      await sdbEntityStoreRef.record(key).delete(db);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1
          ..deleted.v = 1,
      ]);
    });

    test('delete/put record', () async {
      // syncedDbDebug = devWarning(true);
      var db = await syncedDb.database;
      var key = (await sdbEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      await syncedDb.clearSyncRecords(null);
      var ref = sdbEntityStoreRef.record(key);

      await ref.delete(db);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1
          ..deleted.v = 1,
      ]);
      await (ref.cv()..name.v = 'updated').put(db);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = 1,
      ]);
    });

    test('putRecord', () async {
      var record = sdbEntityStoreRef.record('test');
      var database = await syncedDb.database;
      await (record.cv()..name.v = 'test').put(database);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = 'test'
          ..dirty.v = 1,
      ]);

      /// Manually delete the sync record so that it gets re-created
      await syncedDb.scvSyncRecordStoreRef.record(1).delete(database);

      await (record.cv()..name.v = 'test2').put(database);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = 'test'
          ..dirty.v = 1,
      ]);
    });
    /*
    test('delete record', () async {
      var record = sdbEntityStoreRef.record('test_delete');
      var database = await syncedDb.database;
      await record.rawRef.delete(database);
      expect(await syncedDb.getSyncRecords(), isEmpty);
      syncedDb.trackChangesDisabled = true;
      await record.rawRef.add(database, {'1': '2'});
      syncedDb.trackChangesDisabled = false;
      expect(await syncedDb.getSyncRecords(), isEmpty);
      await record.rawRef.delete(database);
      expect(await syncedDb.getSyncRecords(), [
        SdbSyncRecord()
          ..store.v = sdbEntityStoreRef.name
          ..key.v = 'test_delete'
          ..dirty.v = true
          ..deleted.v = true,
      ]);
    });
    test('ext', () async {
      var record = sdbEntityStoreRef.record('test_ext');
      var database = await syncedDb.database;
      var artist = record.cv()..name.v = 'test';
      await artist.put(database);
      expect((await record.get(database)), artist);
      expect((await sdbEntityStoreRef.query().getRecords(database)), [artist]);

      var map = (await record.get(database))!;
      expect(map, artist);
      map.field('name')!.v = 'another';
      map.field('name2')?.v = 'another2';
      expect(map.toMap(), {'name': 'another'});
    });

    test('export', () async {
      var record = sdbEntityStoreRef.record('export');
      var database = await syncedDb.database;
      var artist = record.cv()..name.v = 'test';
      await artist.put(database);
      expect((await record.get(database)), artist);
      expect(await exportDatabaseLines(database), [
        {'sembast_export': 1, 'version': 1},
        {'store': 'entity'},
        [
          'export',
          {'name': 'test'},
        ],
        {'store': 'local_sync_record'},
        [
          1,
          {'store': 'entity', 'key': 'export', 'dirty': true},
        ],
      ]);
    });*/
  });
}
