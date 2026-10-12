import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:test/test.dart';

final _store = SdbStoreRef<String, SdbModel>('my_store');

final _schema = SdbDatabaseSchema(
  stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
);

SyncedSdb _newSyncedSdb() => SyncedSdb.newInMemory(
  options: SyncedSdbOptions(
    openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
  ),
);

void main() {
  test('closed while the meta info is being read', () async {
    // The close lands at every step of the read the listener triggers.
    for (var step = 0; step < 30; step++) {
      var syncedSdb = _newSyncedSdb();
      await syncedSdb.database;
      syncedSdb.onSyncMetaInfo().listen((_) {});
      for (var i = 0; i < step; i++) {
        await Future<void>.value();
      }
      await syncedSdb.close();
    }
    // Let the reads end.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
