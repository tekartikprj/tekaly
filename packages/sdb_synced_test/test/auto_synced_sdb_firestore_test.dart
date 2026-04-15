import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
// ignore: unused_import
import 'package:tekartik_common_utils/dev_utils.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

Future<void> main() async {
  // syncedSdbDebug = devWarning(true);
  group('open sync', () {
    var store = sdbEntityStoreRef;
    var record = store.record('key');
    cvAddConstructor(DbEntity.new);
    late AutoSynchronizedFirestoreSyncedSdb syncedSdb;
    setUp(() async {});

    test('firestore location', () async {
      var firestore = newFirestoreMemory(); //.debugQuickLoggerWrapper();
      // print('app1: ${firestore.app.hashCode}');
      var databaseFactory = newSdbFactoryMemory();
      var rootPath = 'test/location';
      var options = AutoSynchronizedFirestoreSyncedSdbOptions(
        syncedSdbOptions: sdbEntityOptions,

        firestore: firestore,
        databaseFactory: databaseFactory,
        rootDocumentPath: rootPath,
        dbName: 'custom.db',
      );
      syncedSdb = await AutoSynchronizedFirestoreSyncedSdb.open(
        options: options,
      );
      expect(syncedSdb, isNotNull);
      var db = syncedSdb.database;
      expect(db.name, 'custom.db');
      await syncedSdb.initialSynchronizationDone();
      await record.add(db, DbEntity()..name.v = 'test');
      await syncedSdb.synchronize();
      await syncedSdb.close();
      expect((await firestore.doc('test/location/meta/info').get()).data, {
        'lastChangeId': 1,
      });
    });
    test('add', () async {
      // debugSyncedSync = true;
      // syncedSdbDebug = devTrue;
      var firestore = newFirestoreMemory(); // .debugQuickLoggerWrapper();
      var databaseFactory = newSdbFactoryMemory();
      var options = AutoSynchronizedFirestoreSyncedSdbOptions(
        firestore: firestore,
        syncedSdbOptions: sdbEntityOptions,
        databaseFactory: databaseFactory,
        dbName: 'synced.db',
      );
      syncedSdb = await AutoSynchronizedFirestoreSyncedSdb.open(
        options: options,
      );

      expect(syncedSdb, isNotNull);
      var db = syncedSdb.database;
      expect(db.name, 'synced.db');
      await syncedSdb.initialSynchronizationDone();
      await record.add(db, DbEntity()..name.v = 'test');
      // Ensure synchronization
      await sleep(500);

      await syncedSdb.close();
      await databaseFactory.deleteDatabase(db.name);
      syncedSdb = await AutoSynchronizedFirestoreSyncedSdb.open(
        options: options,
      );
      db = syncedSdb.database;
      expect(await record.get(db), isNull);
      await syncedSdb.initialSynchronizationDone();
      expect(await record.get(db), DbEntity()..name.v = 'test');
      await syncedSdb.close();
    });
  });
  group('auto', () {
    var store = sdbEntityStoreRef;
    var record = store.record('key');
    late AutoSynchronizedFirestoreSyncedSdb syncedSdb;
    setUp(() async {
      var firestore = newFirestoreMemory(); //.debugQuickLoggerWrapper();
      var databaseFactory = newSdbFactoryMemory();
      syncedSdb = await AutoSynchronizedFirestoreSyncedSdb.open(
        options: AutoSynchronizedFirestoreSyncedSdbOptions(
          syncedSdbOptions: sdbEntityOptions,
          firestore: firestore,
          databaseFactory: databaseFactory,
          dbName: 'auto.db',
        ),
      );
    });
    tearDown(() async {
      await syncedSdb.close();
    });
    test('add', () async {
      expect(syncedSdb, isNotNull);
      var db = syncedSdb.database;
      await syncedSdb.initialSynchronizationDone();
      expect(await record.get(db), isNull);
      await record.add(db, DbEntity()..name.v = 'test');
      await sleep(1000);
    });
  });
}
