---
name: tekaly-sdb-synced-synced-sdb
description: >-
  Use when opening an sdb (idb_shim) database synchronized with a remote
  source (SyncedSdb, SyncedSdbSynchronizer, AutoSynchronizedFirestoreSyncedSdb)
  with tekaly_sdb_synced: schema with the sync stores, options, firestore auto
  sync and read-only sync.
---

# Synced sdb database (tekaly_sdb_synced)

`SyncedSdb` wraps an sdb `SdbDatabase` (idb_shim, indexed db on the web,
sqflite/sembast elsewhere), tracks local changes in `local_sync_record` and
the last synchronized change id in `local_sync_meta`. `SyncedSdbSynchronizer`
synchronizes it with any `SyncedSource` from `tekaly_synced_db_common`
(memory, firestore, api, rpc). Same behavior as `tekaly_sembast_synced`, only
the local database api differs.

## Guidelines

* Import `package:tekaly_sdb_synced/synced_sdb.dart`; `synced_source.dart`
  adds `SyncedSourceMemory` and the source export/import helpers;
  `synced_sdb_firestore.dart` adds `SyncedSourceFirestore` and
  `AutoSynchronizedFirestoreSyncedSdb`; `sdb_scv.dart` re-exports sdb and the
  cv helpers (`ScvStringRecordBase`, `scvStringStoreFactory`).
* sdb needs a schema: always spread `syncedSdbMetaSchema.stores` into your
  `SdbDatabaseSchema` next to your own stores, and pass it through
  `SyncedSdbOptions(openDatabaseOptions: SdbOpenDatabaseOptions(version:,
  schema:))`. Bump the version when stores change.
* Only stores with `String` keys and `SdbModel` (map) values are synced.
  Values hold `num`, `String`, `bool`, `List`, `Map`, `SdbTimestamp` and
  `SdbBlob` (the sembast `Timestamp`/`Blob` types). Store names starting with
  `local_` are never synced (`SyncedSdb.unsyncedStoreNamePrefix`), keep
  purely local data there.
* Open with `SyncedSdb.openDatabase(name:, databaseFactory:, options:)`,
  `SyncedSdb.fromOpenedDb(openedDatabase:, options:)`, or
  `SyncedSdb.newInMemory(options:)` in tests. Read/write through
  `await syncedSdb.database`; change tracking uses sdb `onChanges` listeners.
  Wait for `syncedSdb.ready` before relying on tracking.
* One `SyncedSdbSynchronizer(db:, source:)` per database; `sync()` (up then
  down), `syncUp()`, `syncDown()`, `lazySync()` (coalesced). `readSource:`
  alone gives a read-only synchronizer, `readSource:` + `writeSource:` a
  hybrid one. `await synchronizer.close()` before `syncedSdb.close()`.
* `autoSync: true` syncs on remote meta changes (`readSource.onMetaInfo`) and
  local dirty records; `syncedSdb.initialSynchronizationDone()` waits for the
  first sync. `syncedSdb.onSyncMetaInfo()` streams the local sync meta.
* In auto sync mode a failed sync is retried (`retryOptions:`, a
  `SyncedDbSynchronizerRetryOptions`): while the first sync has not succeeded,
  every 5s during 1mn then growing to reach 1mn after 5mn of retrying; once it
  is done, 15s doubling up to 1mn. Reset on success. So
  `initialSynchronizationDone()` terminates once the source is reachable
  again instead of waiting forever. `onSyncError()` streams the failures,
  `SyncedDbSynchronizerRetryOptions.noRetry()` disables retrying.
* Sync record flags are ints (`dirty`, `deleted`: 0/1); use `isDirty` /
  `isDeleted`.
* Conflict rule: a remote record with a strictly greater change id wins over a
  local dirty change; otherwise the local change is pushed.
* Firestore: `AutoSynchronizedFirestoreSyncedSdb.open(options:
  AutoSynchronizedFirestoreSyncedSdbOptions(syncedSdbOptions:, firestore:,
  databaseFactory:, rootDocumentPath:, dbName:, readOnly:, retryOptions:))`.
* `SyncedSdbReadMinService.syncedDb(syncedDb:)` /
  `.syncedSource(syncedSource:)` read one record locally or remotely with the
  same api. `mapSdbToSyncedDb` / `mapSyncedDbToSdb` convert values when
  talking to a source directly.

## Examples

### Schema, open and synchronize

```dart
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';

final entityStore = SdbStoreRef<String, SdbModel>('entity');

final schema = SdbDatabaseSchema(
  stores: [entityStore.schema(), ...syncedSdbMetaSchema.stores],
);

final options = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: schema),
);

Future<void> main() async {
  var syncedSdb = SyncedSdb.openDatabase(
    name: 'app.db',
    databaseFactory: newSdbFactoryMemory(), // or the app sdb factory
    options: options,
  );
  var db = await syncedSdb.database;
  await entityStore.record('a1').put(db, {'name': 'test', 'ts': SdbTimestamp.now()});

  var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: SyncedSourceMemory());
  print(await synchronizer.sync()); // SyncedSyncStat({remoteCreatedCount: 1})

  await synchronizer.close();
  await syncedSdb.close();
}
```

### cv records

```dart
import 'package:tekaly_sdb_synced/sdb_scv.dart';

class DbEntity extends ScvStringRecordBase {
  final name = CvField<String>('name');
  final timestamp = CvField<SdbTimestamp>('timestamp');

  @override
  List<CvField> get fields => [name, timestamp];
}

final dbEntityStore = scvStringStoreFactory.store<DbEntity>('entity');

Future<void> save(SdbDatabase db) async {
  cvAddConstructor(DbEntity.new);
  await (dbEntityStore.record('a1').cv()..name.v = 'test').put(db);
}
```

### Firestore, automatically synchronized, read-only client

```dart
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';

Future<AutoSynchronizedFirestoreSyncedSdb> openPublicDb({
  required Firestore firestore,
  required SdbFactory databaseFactory,
  required SyncedSdbOptions options,
}) async {
  var syncedSdb = await AutoSynchronizedFirestoreSyncedSdb.open(
    options: AutoSynchronizedFirestoreSyncedSdbOptions(
      syncedSdbOptions: options,
      firestore: firestore,
      databaseFactory: databaseFactory,
      rootDocumentPath: 'project/my_project/sync/public',
      dbName: 'public.db',
      readOnly: true,
    ),
  );
  await syncedSdb.initialSynchronizationDone();
  return syncedSdb;
}
```
