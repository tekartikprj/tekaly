# tekaly_sembast_synced

A local [sembast](https://pub.dev/packages/sembast) database kept in sync
with a remote *synced source* (Firestore, an api, an in memory source in
tests): local writes are tracked and pushed, remote changes are pulled.

For new code use `tekaly_sdb_synced`, the same synchronization on an sdb
(idb_shim) database; this package serves the existing sembast based apps.
Both share `tekaly_synced_db_common` (sources, sync algorithm) and the tekaly
export format.

- `SyncedDb`: your sembast database plus two sync stores, every local write
  tracked.
- `SyncedDbSynchronizer`: sync up then down against a `SyncedSource`, on
  demand or automatically, with retries.
- `AutoSynchronizedFirestoreSyncedDb`: database, Firestore source and auto
  sync in one call.
- Export and import (memory, files, Flutter assets, Firebase Storage).

Pure Dart: io, web and Flutter.

## Getting started

Not on pub.dev, add the git dependency:

```yaml
dependencies:
  tekaly_sembast_synced:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/sembast_synced
```

```dart
import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';

final noteStore = stringMapStoreFactory.store('note');

Future<void> main() async {
  var syncedDb = SyncedDb.openDatabase(
    databaseFactory: newDatabaseFactoryMemory(), // the app factory in an app
    name: 'notes.db',
    options: SyncedDbOptions(syncedStoreNames: [noteStore.name]),
  );
  var db = await syncedDb.database;
  await noteStore.record('n1').put(db, {'title': 'Hello'});

  var synchronizer = SyncedDbSynchronizer(
    db: syncedDb,
    source: SyncedSourceMemory(), // SyncedSourceFirestore in an app
  );
  print(await synchronizer.sync()); // SyncedSyncStat({remoteCreatedCount: 1})

  await synchronizer.close();
  await syncedDb.close();
}
```

## Which import

| Import | For |
|---|---|
| `synced_db.dart` | `SyncedDb`, `SyncedDbSynchronizer`, `SyncedSourceMemory`, export/import in memory (exports sembast) |
| `synced_db_firestore.dart` | `SyncedSourceFirestore`, `AutoSynchronizedFirestoreSyncedDb` |
| `synced_db_io.dart` | export to / import from files (io only) |
| `synced_db_asset.dart` | import from Flutter assets |
| `synced_db_storage.dart` | export to / import from Firebase Storage |
| `synced_db_sembast.dart` | `SyncedSourceSembast`, a source on a sembast database |

## Pitfalls

- Synced stores have `String` keys and map values holding `num`, `String`,
  `bool`, `List`, `Map`, `Timestamp` and `Blob` only. Every store is synced
  but the system ones, the ones starting with `local_` or ending with
  `_local`, unless `SyncedDbOptions(syncedStoreNames:)` or `predicate:`
  restricts them.
- A store added to `syncedStoreNames` by an app upgrade does not get the
  records written before the client's last sync: bump the source meta
  `version` with the upgrade, every client then reads the whole source again.
- `await synchronizer.close()` before `syncedDb.close()`.
- An import is applied only when the export `lastChangeId` is above the
  local one, or its source version differs: export after a `sync()`.

Package skills (for AI coding agents, `skills/`):
`tekaly-sembast-synced-synced-db` and `tekaly-sembast-synced-export-import`.
