# tekaly_sdb_synced

A local [sdb](https://pub.dev/packages/idb_shim) database (idb_shim: IndexedDB
on the web, sqflite or sembast elsewhere) kept in sync with a remote *synced
source* (Firestore, an api, an in memory source in tests). Local writes are
tracked and pushed, remote changes are pulled. This is the local database to
use for new code; `tekaly_sembast_synced` is its legacy sembast twin.

- `SyncedSdb`: your database plus two sync stores, every local write tracked.
- `SyncedSdbSynchronizer`: sync up then down against a `SyncedSource`, on
  demand or automatically, with retries.
- `AutoSynchronizedFirestoreSyncedSdb`: database, Firestore source and auto
  sync in one call.
- Export and import in the tekaly export format (shared with
  `tekaly_sembast_synced` and the sources), publishing to Firebase Storage
  for many readers.

Pure Dart: io, web and Flutter (mobile, desktop, web). The source
abstraction and the sync algorithm come from `tekaly_synced_db_common`.

## Getting started

Not on pub.dev, add the git dependency:

```yaml
dependencies:
  tekaly_sdb_synced:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/sdb_synced
```

```dart
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';

final noteStore = SdbStoreRef<String, SdbModel>('note');

final options = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      // Your stores and the sync stores.
      stores: [noteStore.schema(), ...syncedSdbMetaSchema.stores],
    ),
  ),
);

Future<void> main() async {
  var syncedSdb = SyncedSdb.openDatabase(
    name: 'notes.db',
    databaseFactory: newSdbFactoryMemory(), // the app factory in an app
    options: options,
  );
  var db = await syncedSdb.database;
  await noteStore.record('n1').put(db, {'title': 'Hello'});

  var synchronizer = SyncedSdbSynchronizer(
    db: syncedSdb,
    source: SyncedSourceMemory(), // SyncedSourceFirestore in an app
  );
  print(await synchronizer.sync()); // SyncedSyncStat({remoteCreatedCount: 1})

  await synchronizer.close();
  await syncedSdb.close();
}
```

In a Flutter app the database factory is
`getSdbFactory(packageName: ...)` of `tekartik_app_flutter_idb`
(`package:tekartik_app_flutter_idb/sdb.dart`): IndexedDB on the web, sqflite
on mobile, a file per database on desktop.

## Which import

| Import | For |
|---|---|
| `synced_sdb.dart` | `SyncedSdb`, `SyncedSdbSynchronizer`, export/import in memory |
| `sdb_scv.dart` | sdb itself and the cv record helpers (`ScvStringRecordBase`, `scvStringStoreFactory`) |
| `synced_source.dart` | `SyncedSourceMemory` and the source export/import helpers |
| `synced_sdb_firestore.dart` | `SyncedSourceFirestore`, `AutoSynchronizedFirestoreSyncedSdb` |
| `synced_sdb_io.dart` | export to / import from files (io only) |
| `synced_sdb_storage.dart` | publish to Firebase Storage, read it back (Storage api or http) |

## Pitfalls

- The schema must hold `syncedSdbMetaSchema.stores`; bump the version when
  the stores change.
- Synced stores have `String` keys and map values holding `num`, `String`,
  `bool`, `List`, `Map`, `SdbTimestamp` and `SdbBlob` only. Stores whose name
  starts with `local_` are never synced: keep purely local data there.
- Only the stores of the local schema are synced: the records of a store the
  schema does not know are skipped, and the sync goes on past them. When an
  app upgrade adds a store, its records written before are not fetched: bump
  the source meta `version` (`source.putMetaInfo(CvMetaInfo()..version.v =
  2)`), every client then reads the whole source again.
- `await synchronizer.close()` before `syncedSdb.close()`.
- An import (`importFromMemory`, `fetchAndImport`...) is applied only when the
  export `lastChangeId` is above the local one, or its source version differs:
  export after a `sync()`.

Package skills (for AI coding agents, `skills/`):
`tekaly-sdb-synced-synced-sdb` (open, synchronize, Firestore) and
`tekaly-sdb-synced-export-import` (export, import, Storage publishing).
