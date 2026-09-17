---
name: tekaly-firestore-synced-sdb-mirror
description: >-
  Use when mirroring a tracked firestore collection into a local sdb store
  with tekaly_firestore_synced (SyncedFsSdbSynchronizer, syncedFsSdbSchema),
  including full resync rules and the dead letter queue.
---

# Local sdb mirror of a synced firestore collection (tekaly_firestore_synced)

## Guidelines

* Import `package:tekaly_firestore_synced/synced_firestore_sdb.dart` (client
  side, also exports `synced_firestore.dart`).
* Spread `syncedFsSdbSchema.stores` into the local `SdbDatabaseSchema` next to
  the mirrored store (`SdbStoreRef<String, SdbModel>`); the bookkeeping lives
  in `local_fs_sync_meta` (one record per mirrored store) and
  `local_fs_sync_dlq`.
* Create `SyncedFsSdbSynchronizer(source:, database:, store:)` with a
  `SyncedFsFirestoreSource(firestore:, path:)` (or `coll.source`) and call
  `sync()`; it replays the change log from the last applied change id and
  does a full resynchronization when the mirror is new, bound to another
  source, behind a truncated log or when the source version was bumped.
  Check `SyncedFsSdbSyncResult` (`fullSync`, `appliedCount`, `deletedCount`,
  `isEmpty`).
* Documents land in the store keyed by their firestore document id with the
  `synced` map stripped; applying a change is an idempotent put or delete.
* A change that cannot be applied goes to the dead letter queue instead of
  failing the sync: inspect with `getDeadLetters()`, replay with
  `retryDeadLetters()`.
* Firestore values are converted with `firestoreMapToSdb` (timestamps become
  `SdbTimestamp`, blobs `SdbBlob`); only sdb supported types are stored.
* Prefer firestore's own offline persistence when the app talks to firestore
  directly; use this mirror when data must land in a custom offline store.

## Examples

```dart
import 'package:tekaly_firestore_synced/synced_firestore_sdb.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

final itemStoreRef = SdbStoreRef<String, SdbModel>('item');

final schema = SdbDatabaseSchema(
  stores: [itemStoreRef.schema(), ...syncedFsSdbSchema.stores],
);

Future<SyncedFsSdbSynchronizer> openMirror(
  Firestore firestore,
  SdbFactory factory,
) async {
  var db = await factory.openDatabase(
    'app.db',
    options: SdbOpenDatabaseOptions(version: 1, schema: schema),
  );
  var synchronizer = SyncedFsSdbSynchronizer(
    source: SyncedFsFirestoreSource(firestore: firestore, path: 'item'),
    database: db,
    store: itemStoreRef,
  );
  var result = await synchronizer.sync();
  print('full: ${result.fullSync}, applied: ${result.appliedCount}');

  var deadLetters = await synchronizer.getDeadLetters();
  if (deadLetters.isNotEmpty) {
    await synchronizer.retryDeadLetters();
  }
  return synchronizer;
}
```
