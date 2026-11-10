import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:test/test.dart';

final _store = stringMapStoreFactory.store('my_store');

void main() {
  group('synced_db_regression', () {
    test('close while the database is opening', () async {
      var syncedDb = SyncedDb(
        name: 'closed_while_opening.db',
        databaseFactory: newDatabaseFactoryMemory(),
      );
      var dbFuture = syncedDb.database;
      await syncedDb.close();
      var db = await dbFuture;
      await expectLater(
        _store.record('a').put(db, {'v': 1}),
        throwsA(anything),
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('database requested twice, changes tracked once', () async {
      var syncedDb = SyncedDb.newInMemory(syncedStoreNames: [_store.name]);
      var futures = [syncedDb.database, syncedDb.database];
      var db = (await Future.wait(futures)).first;
      await _store.record('a').put(db, {'v': 1});
      expect(await syncedDb.txnGetDirtySyncRecords(db), hasLength(1));
      await syncedDb.close();
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
