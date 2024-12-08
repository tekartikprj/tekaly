import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/src/api/import_common.dart';
import 'package:tekaly_sembast_synced/src/sync/auto_synced_db_firestore.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

Future<void> main() async {
  // syncedDbDebug = devWarning(true);
  group('open sync', () {
    var store = stringMapStoreFactory.store('test');
    var record = store.record('key');
    late AutoSynchronizedFirestoreSyncedDb syncedDb;
    setUp(() async {});

    test('add', () async {
      // debugSyncedSync = true;
      var firestore = newFirestoreMemory(); //.debugQuickLoggerWrapper();
      var databaseFactory = newDatabaseFactoryMemory();
      var options = AutoSynchronizedFirestoreSyncedDbOptions(
          firestore: firestore, databaseFactory: databaseFactory);
      syncedDb = await AutoSynchronizedFirestoreSyncedDb.open(options: options);
      expect(syncedDb, isNotNull);
      var db = syncedDb.database;
      await syncedDb.initialSynchronizationDone();
      await record.add(db, {'test': 1});
      await syncedDb.close();
      await databaseFactory.deleteDatabase(SyncedDb.nameDefault);
      syncedDb = await AutoSynchronizedFirestoreSyncedDb.open(options: options);
      db = syncedDb.database;
      await syncedDb.initialSynchronizationDone();
      expect(await record.get(db), {'test': 1});
    }, skip: 'not working yet');
  });
  group('auto', () {
    var store = stringMapStoreFactory.store('test');
    var record = store.record('key');
    late AutoSynchronizedFirestoreSyncedDb syncedDb;
    setUp(() async {
      var firestore = newFirestoreMemory(); // .debugQuickLoggerWrapper();
      var databaseFactory = newDatabaseFactoryMemory();
      syncedDb = await AutoSynchronizedFirestoreSyncedDb.open(
          options: AutoSynchronizedFirestoreSyncedDbOptions(
              firestore: firestore, databaseFactory: databaseFactory));
    });
    tearDown(() async {
      await syncedDb.close();
    });
    test('add', () async {
      expect(syncedDb, isNotNull);
      var db = syncedDb.database;
      await syncedDb.initialSynchronizationDone();
      expect(await record.get(db), isNull);
      await record.add(db, {'test': 1});
    });
  });
}
