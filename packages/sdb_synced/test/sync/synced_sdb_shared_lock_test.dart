import 'package:idb_shim/idb_sdb.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

final _store = SdbStoreRef<String, SdbModel>('my_store');

/// A remote taking its time to write: a tab checking a record (not pushed
/// yet) while another tab writes it pushes it too.
class _SlowWriteSource extends SyncedSourceMemory {
  @override
  Future<CvSyncedSourceRecord> putSourceRecord(
    CvSyncedSourceRecord record,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.putSourceRecord(record);
  }
}

final _options = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
    ),
  ),
);

void main() {
  test('no shared lock in memory', () async {
    var syncedSdb = SyncedSdb.newInMemory(options: _options);
    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
      source: SyncedSourceMemory(),
    );
    expect(synchronizer.sharedSyncLockName, isNull);
    await synchronizer.close();
    await syncedSdb.close();
  });

  group('browser', () {
    var name = 'synced_sdb_shared_lock_test.db';

    setUp(() async {
      await sdbFactoryWeb.deleteDatabase(name);
    });
    tearDown(() async {
      await sdbFactoryWeb.deleteDatabase(name);
    });

    test('lock name', () async {
      SyncedSdbSynchronizer synchronizer(SdbFactory factory) =>
          SyncedSdbSynchronizer(
            db: SyncedSdb(
              databaseFactory: factory,
              name: name,
              options: _options,
            ),
            source: SyncedSourceMemory(),
          );
      expect(
        synchronizer(sdbFactoryWeb).sharedSyncLockName,
        'tekaly_synced_sdb:idb-native:$name',
      );
      expect(
        synchronizer(sdbFactoryWeb.sandbox(path: 'app')).sharedSyncLockName,
        'tekaly_synced_sdb:sandbox(idb-native, app):$name',
      );
    });

    test('two tabs on the same database push a change once', () async {
      var source = _SlowWriteSource();
      // Two tabs: two connections to the same IndexedDB database, each with
      // its own synchronizer.
      SyncedSdb open() => SyncedSdb(
        databaseFactory: sdbFactoryWeb,
        name: name,
        options: _options,
      );
      var tab1 = open();
      var tab2 = open();
      var synchronizer1 = SyncedSdbSynchronizer(db: tab1, source: source);
      var synchronizer2 = SyncedSdbSynchronizer(db: tab2, source: source);
      addTearDown(() async {
        await synchronizer1.close();
        await synchronizer2.close();
        await tab1.close();
        await tab2.close();
      });
      await _store.record('k1').put(await tab1.database, {'v': 1});
      await tab2.database;

      await Future.wait([
        Future.value(synchronizer1.sync()),
        Future.value(synchronizer2.sync()),
      ]);
      // Pushed by one tab, the other one found it pushed (change 2 when both
      // pushed it).
      expect((await source.getMetaInfo())?.lastChangeId.v, 1);
      expect(
        (await source.getSourceRecordList()).list.map((r) => r.recordKey),
        ['k1'],
      );
    });
  }, testOn: 'browser');
}
