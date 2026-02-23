// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:sembast/utils/sembast_import_export.dart';

import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_test/synced_db_test_common.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:dev_test/test.dart';

void main() {
  cvAddConstructor(DbEntity.new);
  group('synced_db', () {
    late SyncedDb syncedDb;
    setUp(() async {
      syncedDb = SyncedDb.newInMemory(syncedStoreNames: [dbEntityStoreName]);
    });
    tearDown(() async {
      await syncedDb.close();
    });
    test('stores', () async {
      expect(syncedDb.dbSyncMetaStoreRef.name, 'syncMeta');
      expect(syncedDb.dbSyncRecordStoreRef.name, 'syncRecord');
      expect(syncedDb.options.syncedStoreNames, ['entity']);
    });
    test('add/delete record', () async {
      var db = await syncedDb.database;
      var key = (await dbEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true,
      ]);
      await dbEntityStoreRef.record(key).delete(db);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true
          ..deleted.v = true,
      ]);
    });
    test('add/put/delete record', () async {
      var db = await syncedDb.database;
      var key = (await dbEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      var ref = dbEntityStoreRef.record(key);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true,
      ]);
      await (ref.cv()..name.v = 'updated').put(db);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true,
      ]);
      await dbEntityStoreRef.record(key).delete(db);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true
          ..deleted.v = true,
      ]);
    });
    test('delete/put record', () async {
      // syncedDbDebug = devWarning(true);
      var db = await syncedDb.database;
      var key = (await dbEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      await syncedDb.clearSyncRecords(null);
      var ref = dbEntityStoreRef.record(key);

      await ref.delete(db);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true
          ..deleted.v = true,
      ]);
      await (ref.cv()..name.v = 'updated').put(db);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = key
          ..dirty.v = true,
      ]);
    });
    test('putRecord', () async {
      var record = dbEntityStoreRef.record('test');
      var database = await syncedDb.database;
      await (record.cv()..name.v = 'test').put(database);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'test'
          ..dirty.v = true,
      ]);

      /// Manually delete the sync record so that it gets re-created
      await syncedDb.dbSyncRecordStoreRef.record(1).delete(database);

      await (record.cv()..name.v = 'test2').put(database);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'test'
          ..dirty.v = true,
      ]);
    });

    test('delete record', () async {
      var record = dbEntityStoreRef.record('test_delete');
      var database = await syncedDb.database;
      await record.rawRef.delete(database);
      expect(await syncedDb.getSyncRecords(), isEmpty);
      syncedDb.trackChangesDisabled = true;
      await record.rawRef.add(database, {'1': '2'});
      syncedDb.trackChangesDisabled = false;
      expect(await syncedDb.getSyncRecords(), isEmpty);
      await record.rawRef.delete(database);
      expect(await syncedDb.getSyncRecords(), [
        DbSyncRecord()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'test_delete'
          ..dirty.v = true
          ..deleted.v = true,
      ]);
    });
    test('ext', () async {
      var record = dbEntityStoreRef.record('test_ext');
      var database = await syncedDb.database;
      var artist = record.cv()..name.v = 'test';
      await artist.put(database);
      expect((await record.get(database)), artist);
      expect((await dbEntityStoreRef.query().getRecords(database)), [artist]);

      var map = (await record.get(database))!;
      expect(map, artist);
      map.field('name')!.v = 'another';
      map.field('name2')?.v = 'another2';
      expect(map.toMap(), {'name': 'another'});
    });

    test('export', () async {
      var record = dbEntityStoreRef.record('export');
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
        {'store': 'syncRecord'},
        [
          1,
          {'store': 'entity', 'key': 'export', 'dirty': true},
        ],
      ]);
    });
  });
  group('local synced_db', () {
    late SyncedDb syncedDb;
    setUp(() async {
      syncedDb = SyncedDb.newInMemory();
    });
    tearDown(() async {
      await syncedDb.close();
    });
    test('add record', () async {
      var db = await syncedDb.database;
      (await dbLocalEntityStoreRef.add(
        db,
        DbEntity()..name.v = 'test',
      )).rawRef.key;
      expect(await syncedDb.getSyncRecords(), isEmpty);
    });
  });
}
