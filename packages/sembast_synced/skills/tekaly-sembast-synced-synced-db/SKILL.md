---
name: tekaly-sembast-synced-synced-db
description: >-
  Use when opening a sembast database synchronized with a remote source
  (SyncedDb, SyncedDbSynchronizer, AutoSynchronizedFirestoreSyncedDb) with
  tekaly_sembast_synced: store rules, options, firestore auto sync and
  read-only sync.
---

# Synced sembast database (tekaly_sembast_synced)

`SyncedDb` wraps a sembast `Database`, tracks local changes in the
`local_sync_record` store and keeps the last synchronized change id in
`local_sync_meta`. A `SyncedDbSynchronizer` pushes dirty records to a
`SyncedSource` (sync up) and pulls remote changes (sync down). The source
abstraction, records and the synchronizer base come from
`tekaly_synced_db_common`.

## Guidelines

* Import `package:tekaly_sembast_synced/synced_db.dart` (exports sembast too);
  `synced_db_firestore.dart` adds `SyncedSourceFirestore` and
  `AutoSynchronizedFirestoreSyncedDb`; `synced_db_internals.dart` exposes the
  sync records, mixins and `SyncedDbCommon` for advanced use.
* Only stores with `String` keys and `Map<String, Object?>` values are
  synchronized. Use `stringMapStoreFactory` or `cvStringStoreFactory` /
  `DbStringRecordBase` (`tekartik_app_cv_sembast`). Values hold `num`, `String`,
  `bool`, `List`, `Map`, `Timestamp` and `Blob` only.
* Every store is synced by default except the system stores, stores starting
  with `local_` (`unsyncedLocalStoreNamePrefix`) and stores ending with
  `_local`. Restrict with `SyncedDbOptions(syncedStoreNames: [...])` or
  `SyncedDbOptions(predicate: (store) => ...)`. Keep purely local data in a
  `local_` store.
* Open with `SyncedDb.openDatabase(databaseFactory:, name:, options:)`, wrap an
  already opened database with `SyncedDb.fromOpenedDb(openedDatabase:)`, use
  `SyncedDb.newInMemory()` in tests. Read/write records through
  `await syncedDb.database`: change tracking is automatic.
* Create one `SyncedDbSynchronizer(db:, source:)` per database. `sync()` runs
  sync up then sync down under a lock (concurrent calls share the run);
  `syncUp()` / `syncDown()` run one direction. Always `await synchronizer.close()`
  before `syncedDb.close()`.
* Pass `readSource:` alone for a read-only synchronizer (a public source the
  user cannot write to: local changes stay dirty), `readSource:` +
  `writeSource:` for a hybrid (read from firestore, write through an api).
* `autoSync: true` synchronizes on remote meta info changes and on local dirty
  records. Wait for the first sync with `syncedDb.initialSynchronizationDone()`.
* In auto sync mode a failed sync is retried (`retryOptions:`, a
  `SyncedDbSynchronizerRetryOptions`): every 5s while the first sync has not
  succeeded, then 15s doubling up to 1mn, reset on success. So
  `initialSynchronizationDone()` terminates once the source is reachable
  again instead of waiting forever. `onSyncError()` streams the failures,
  `SyncedDbSynchronizerRetryOptions.noRetry()` disables retrying.
* Conflict rule: a remote record with a strictly greater change id wins over a
  local dirty change; otherwise the local change is pushed. Deleting a record
  locally pushes a deletion; a remote deletion deletes locally.
* For firestore use `AutoSynchronizedFirestoreSyncedDb.open(options:)`: it
  opens the database, creates the `SyncedSourceFirestore` at `rootDocumentPath`
  and an auto synchronizer. `readOnly: true` for public data, `retryOptions:`
  to change the retry strategy.
* `SyncedDbReadMinService.syncedDb(syncedDb:)` /
  `SyncedDbReadMinService.syncedSource(syncedSource:)` read one record from
  the local database or the remote source with the same api.
* `debugSyncedDbSynchronizer = true` traces the synchronization (dev only).

## Examples

### Local database synchronized with an in memory source

```dart
import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';

Future<void> main() async {
  var syncedDb = SyncedDb.openDatabase(
    databaseFactory: newDatabaseFactoryMemory(),
    name: 'app.db',
    options: SyncedDbOptions(syncedStoreNames: ['entity']),
  );
  var db = await syncedDb.database;
  var store = stringMapStoreFactory.store('entity');
  await store.record('a1').put(db, {'name': 'test'});

  var source = SyncedSourceMemory(); // any SyncedSource
  var synchronizer = SyncedDbSynchronizer(db: syncedDb, source: source);
  var stat = await synchronizer.sync();
  print(stat); // SyncedSyncStat({remoteCreatedCount: 1})

  await synchronizer.close();
  await syncedDb.close();
}
```

### Firestore, automatically synchronized

```dart
import 'package:tekaly_sembast_synced/synced_db_firestore.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';

Future<AutoSynchronizedFirestoreSyncedDb> openAppDb({
  required Firestore firestore,
  required DatabaseFactory databaseFactory,
}) async {
  var syncedDb = await AutoSynchronizedFirestoreSyncedDb.open(
    options: AutoSynchronizedFirestoreSyncedDbOptions(
      firestore: firestore,
      databaseFactory: databaseFactory,
      rootDocumentPath: 'project/my_project/sync/data',
      sembastDbName: 'synced.db',
      syncedDbOptions: SyncedDbOptions(syncedStoreNames: ['entity']),
      readOnly: false, // true: never push local changes
    ),
  );
  await syncedDb.initialSynchronizationDone();
  var db = syncedDb.database; // sembast Database
  await stringMapStoreFactory.store('entity').record('k').put(db, {'v': 1});
  await syncedDb.synchronize(); // or rely on the auto sync
  return syncedDb;
}
```

### Read-only and hybrid synchronizers

```dart
import 'package:tekaly_sembast_synced/synced_db.dart';

SyncedDbSynchronizer readOnly(SyncedDb db, SyncedSourceRead publicSource) =>
    SyncedDbSynchronizer(db: db, readSource: publicSource, autoSync: true);

SyncedDbSynchronizer hybrid(
  SyncedDb db,
  SyncedSourceRead firestoreSource,
  SyncedSourceWrite apiSource,
) => SyncedDbSynchronizer(
  db: db,
  readSource: firestoreSource,
  writeSource: apiSource,
);
```
