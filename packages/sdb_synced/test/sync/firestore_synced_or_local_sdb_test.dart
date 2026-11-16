import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

final _store = SdbStoreRef<String, SdbModel>('my_store');

final _openOptions = SdbOpenDatabaseOptions(
  version: 1,
  schema: SdbDatabaseSchema(
    stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
  ),
);

/// An app database class.
class _MyDb extends FirestoreSyncedOrLocalSdb {
  _MyDb(super.db, {super.autoSyncedSdb});

  static Future<_MyDb> openSynced({
    required SdbFactory factory,
    required Firestore firestore,
  }) async {
    var synced = await FirestoreSyncedOrLocalSdb.openAutoSynchronized(
      factory: factory,
      firestore: firestore,
      name: 'my_db.db',
      rootDocumentPath: 'test/my_db',
      options: _openOptions,
    );
    return _MyDb(synced.database, autoSyncedSdb: synced);
  }

  static Future<_MyDb> openLocal({required SdbFactory factory}) async =>
      _MyDb(await factory.openDatabase('my_db.db', options: _openOptions));
}

void main() {
  test('local', () async {
    var db = await _MyDb.openLocal(factory: newSdbFactoryMemory());
    expect(db.isSynced, isFalse);
    expect(db.isFirstSyncDone, isTrue);
    await db.initialSynchronizationDone();
    await db.synchronize();
    await db.resynchronize();
    await _store.record('k1').put(db.db, {'v': 1});
    expect((await _store.record('k1').get(db.db))?.value, {'v': 1});
    await db.close();
  });

  test('synced, seen by another device', () async {
    var firestore = newFirestoreMemory();
    var first = await _MyDb.openSynced(
      factory: newSdbFactoryMemory(),
      firestore: firestore,
    );
    expect(first.isSynced, isTrue);
    await first.initialSynchronizationDone();
    await _store.record('k1').put(first.db, {'v': 1});
    await first.synchronize();
    // Set at the end of the first sync down, after an explicit one surely.
    expect(first.isFirstSyncDone, isTrue);
    await first.close();

    var second = await _MyDb.openSynced(
      factory: newSdbFactoryMemory(),
      firestore: firestore,
    );
    await second.initialSynchronizationDone();
    expect((await _store.record('k1').get(second.db))?.value, {'v': 1});

    // Read everything again: the record stays.
    await second.resynchronize();
    expect((await _store.record('k1').get(second.db))?.value, {'v': 1});
    await second.close();
  });
}
