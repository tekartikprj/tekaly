# tekaly_firestore_synced

Sync a whole firestore collection offline, into a local sdb store, with a
minimal number of reads — the firestore counterpart of
[`tekaly_sdb_synced`](../sdb_synced), which syncs a whole local database from a
generic source.

The difference: here the *source of truth is an ordinary firestore collection*
that other writers (apps, admin scripts, cloud functions) keep writing to. The
package adds the bookkeeping that makes such a collection incrementally
consumable, plus a local mirror that consumes it.

## Design

### Every document carries a modification number

Each document gets a `synced` sub map:

```json
{
  "title": "some item",
  "synced": {"changeId": 42, "deleted": false, "timestamp": "2026-08-31T…"}
}
```

`synced.changeId` is the **modification number**: a strictly increasing number,
unique in the collection, allocated on every write from `lastChangeId` in
`<collection>_meta/info`, in the same transaction as the document. It is what a
consumer resumes from. `synced.timestamp` is the server update time, what the
scheduled reconciliation walks. Deletions are *soft*: the document stays as a
tombstone with `deleted: true`, so a consumer can pick the deletion up (a hard
deletion leaves nothing to reconcile from).

### An immutable change log

One entry per modification in `<collection>_changes`, whose document id is the
zero padded modification number, so:

- entries are naturally ordered by id,
- writing the same change twice writes the same document — **idempotent**, which
  matters because firestore triggers are at-least-once.

Entries embed the document content by default, so a consumer synchronizes with
one read per page of changes and never touches the collection itself.

### Primary path, then safety nets

| Path | What it covers | Class |
|---|---|---|
| In the write transaction | writes going through the helper | `SyncedFsCollection` |
| Cloud function trigger | writes going around the helper | `SyncedFsCollectionTrigger` |
| On demand rebuild | trigger failures, backfills | `SyncedFsChangeLogRebuilder.rebuild` |
| Scheduled reconciliation | trigger failures, cheaply | `SyncedFsChangeLogRebuilder.reconcile` |
| Stamping pass | documents never stamped at all | `SyncedFsChangeLogRebuilder.stampMissingChangeIds` |

All of them converge on the same immutable entry, so running several of them,
or the same one twice, is harmless.

### Consumers

A consumer only needs two questions answered, both on `SyncedFsSource`:

- *"give me everything newer than modification number X"* — `getChangeList`,
- *"give me a full snapshot of these document ids"* (or of everything) —
  `getSnapshot`.

`SyncedFsSdbSynchronizer` answers them into a local sdb store: applying a change
is a plain put or delete (idempotent), and a change that cannot be applied goes
to a local dead letter queue instead of blocking the synchronization.

> For a mobile/web client talking to firestore directly, firestore's own offline
> persistence is usually enough. This package is for the case where the data has
> to land in a *custom* offline store (sdb/sembast, a search index, another
> backend).

## Layout

| Library | Side | Content |
|---|---|---|
| `synced_firestore.dart` | client & common | collection helper, models, read only source |
| `synced_firestore_trigger.dart` | server | cloud function trigger, change log rebuild |
| `synced_firestore_sdb.dart` | client | local sdb mirror |

Collection `item` uses 3 firestore paths:

```
item                    the tracked collection
item_changes            the immutable change log
item_meta/info          lastChangeId, version, minIncrementalChangeId, watermarks
```

## Usage

### Writing

```dart
var coll = SyncedFsCollection(
  firestore: firestore,
  collection: CvCollectionReference<DbItem>('item'),
);

await coll.setDoc('k1', DbItem()..title.v = 'hello');
var id = await coll.addDoc(DbItem()..title.v = 'added');
await coll.deleteDoc(id); // tombstone
var item = await coll.getDoc('k1');
```

Each write allocates the next modification number, stamps the document and
appends the change log entry, all in one transaction.

Options:

```dart
SyncedFsCollectionOptions(
  writeChangeLog: false,       // the trigger feeds the change log instead
  changeLogIncludesData: false, // keep the log small, consumers fetch snapshots
)
```

### Cloud function trigger

For writes that do not go through `SyncedFsCollection`. On an `onWrite` trigger
of `item/{docId}`:

```dart
var trigger = SyncedFsCollectionTrigger(firestore: firestore, path: 'item');

await trigger.onDocumentWrite(docId: docId, before: before, after: after);
// or, from snapshots:
await trigger.onDocumentSnapshotWrite(before: before, after: after);
```

It handles every case: a document with no modification number gets one and is
stamped; a content changed behind the helper's back gets a new one; a hard
deletion gets a tombstone entry; an already tracked write is a no-op.

### Rebuild and reconciliation

```dart
var rebuilder = SyncedFsChangeLogRebuilder(firestore: firestore, path: 'item');

// On demand, since modification number X (0 walks the whole collection,
// null resumes from the last complete rebuild).
await rebuilder.rebuild(sinceChangeId: 42);

// From a cron, walking only what was updated recently.
await rebuilder.reconcile(since: const Duration(hours: 1));

// Once, after enabling the helpers on an existing collection.
await rebuilder.stampMissingChangeIds();

// Housekeeping.
await rebuilder.truncateChangeLog(beforeChangeId: 10_000); // consumers below resync
await rebuilder.bumpVersion();                             // force a full resync
```

Both `rebuild` and `reconcile` take a `limit` and report `complete: false` when
they stop on it, so a scheduled job can stay within its time budget and resume
from the returned `lastChangeId`.

A rebuild recovers a *compacted* log: only the current modification number of
each document, since superseded ones are gone from the collection. That is
exactly what a consumer asking for "everything newer than X" needs.

### Local sdb mirror

```dart
var schema = SdbDatabaseSchema(
  stores: [itemStoreRef.schema(), ...syncedFsSdbSchema.stores],
);
var db = await factory.openDatabase(
  'app.db',
  options: SdbOpenDatabaseOptions(version: 1, schema: schema),
);

var synchronizer = SyncedFsSdbSynchronizer(
  source: SyncedFsFirestoreSource(firestore: firestore, path: 'item'),
  database: db,
  store: itemStoreRef, // SdbStoreRef<String, SdbModel>
);

var result = await synchronizer.sync();
```

Documents land in `itemStoreRef` keyed by their firestore document id, with the
`synced` bookkeeping stripped. `sync()` does a full resynchronization when the
mirror is new, bound to another source, left behind a change log truncation, or
when the source version was bumped; otherwise it replays the change log from the
last applied modification number.

Failures are queued, not fatal:

```dart
var deadLetters = await synchronizer.getDeadLetters();
await synchronizer.retryDeadLetters();
```

Local bookkeeping lives in `local_fs_sync_meta` (one record per mirrored store)
and `local_fs_sync_dlq`.

## Trade-offs

- **The meta document is a write hotspot.** Allocating a monotonic modification
  number means one write per collection write on `<collection>_meta/info`,
  bounded by firestore's ~1 write/second per document. Fine for content managed
  by a few writers, not for a high write-rate collection — for those, drop the
  inline path (`writeChangeLog: false`, let the trigger allocate) and lean on
  `reconcile`, or shard the collection.
- **Soft deletions keep tombstones around.** They are what makes deletions
  syncable. Truncating the change log does not remove them; a version bump plus
  a real cleanup does.
- **Change log storage.** Entries embedding the document content double the
  storage of the collection over time. Use `changeLogIncludesData: false` and/or
  `truncateChangeLog` to keep it bounded.

## Setup

`pubspec.yaml`:

```yaml
  tekaly_firestore_synced:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/firestore_synced
```
