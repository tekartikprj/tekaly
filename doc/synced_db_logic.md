# Synchronization logic (synced_db_synchronizer, synced_sdb_synchronizer)

This document describes the current synchronization mechanism implemented in:

- `packages/sembast_synced/lib/src/sync/synced_db_synchronizer.dart` (`SyncedDbSynchronizer`, sembast based)
- `packages/sdb_synced/lib/src/sync/synced_sdb_synchronizer.dart` (`SyncedSdbSynchronizer`, sdb/idb based)

Both share the same base class `SyncedDbSynchronizerCommon` and implement the exact
same logic; only the local database API differs (sembast `Transaction` vs
`SdbTransaction`, `bool` vs `int` for flags, value conversion via
`mapSdbToSyncedDb`/`mapSyncedDbToSdb` on the sdb side).

## Overview

```
+-------------------+        sync up (push dirty)        +-----------------+
|  Local database   | ---------------------------------> |  Synced source  |
|  (SyncedDb /      |                                    |  (dumb storage: |
|   SyncedSdb)      | <--------------------------------- |  firestore,     |
|  - data stores    |     sync down (pull by changeId)   |  memory, export)|
|  - syncRecord     |                                    |  - records      |
|  - syncMetaInfo   |                                    |  - meta info    |
+-------------------+                                    +-----------------+
```

The synchronizer keeps a local database and a remote *sync source* in sync:

- **sync up**: push locally modified (*dirty*) records to the source.
- **sync down**: pull remote changes newer than the last seen `syncChangeId`.
- `sync()` = `syncUp()` then `syncDown()`, guarded by a lock and a single-flight
  wrapper (concurrent calls await the same run).

## The sync source concept (dumb source)

The source (`SyncedSource`) is intentionally **dumb**: it is a plain record store
with no sync intelligence. It only guarantees:

- `putSourceRecord(record)`: store a record, assign a `syncId` if new, assign the
  next incremental `syncChangeId` and a server `syncTimestamp`, update meta
  `lastChangeId`. Returns the stored record (the response is authoritative).
- `getSourceRecordList(afterChangeId, limit, includeDeleted)`: list records ordered
  by `syncChangeId`, after a given change id.
- `getMetaInfo()` / `putMetaInfo()`: a single meta record (see below).
- `onMetaInfo()`: stream of meta changes (native on firestore via snapshots,
  polling otherwise) — used for auto-sync.

Implementations: firestore (`synced_source_firestore.dart`), memory, sembast,
export (read-only export files).

Records are **never removed** from the source by the normal sync flow: a delete is
a record with `deleted: true` (a tombstone), pushed like any other change so other
clients can sync the deletion incrementally.

### Source record format (`CvSyncedSourceRecord`)

| Field | Meaning |
|---|---|
| `syncId` | Unique id of the record in the source (document id in firestore) |
| `syncChangeId` | Incremental change number, allocated by the source on each write |
| `syncTimestamp` | Server timestamp of the last change |
| `record.store` | Local store name |
| `record.key` | Local record key |
| `record.deleted` | Tombstone flag |
| `record.value` | Record content (null when deleted) |

A record is considered deleted if `deleted == true` **or** `value == null`
(some old sync engines did not set the flag correctly).

### Source meta info (`CvMetaInfo`)

| Field | Meaning |
|---|---|
| `lastChangeId` | Highest `syncChangeId` in the source |
| `minIncrementalChangeId` | Below this, incremental sync is not possible (history was purged/exported); clients must full-sync |
| `version` | Source version; bump it to force clients to full re-sync |

## The syncId notion

`syncId` identifies a record **in the source** (e.g. the firestore document id).
It is independent of the local `store`/`key` pair, which identifies the record
locally. The mapping between the two lives in the local sync record.

- A local record with no `syncId` has never been pushed: pushing it is a *remote
  create* (the source generates the id, by default derived from store/key).
- A local record with a `syncId` maps to an existing source record: pushing it is
  a *remote update* of that same source record.

## The local dirty notion (tracking changes)

Next to the data stores, the local database maintains a **sync record store**
(`syncRecord`), one entry per synced data record:

| Field | Meaning |
|---|---|
| `store` / `key` | The data record it tracks |
| `dirty` | Local change not yet pushed |
| `deleted` | Local deletion not yet pushed (data record is gone, sync record remains) |
| `syncId` / `syncTimestamp` / `syncChangeId` | Last known source state for this record |

Tracking is automatic: the db installs an `onChanges` listener on every synced
store (filtered by `shouldSyncStore`). Any application write creates or updates
the matching sync record with `dirty = true` (and `deleted = true` on delete).

During synchronization the synchronizer writes through `syncTransaction`, which
sets `trackChangesDisabled` so that applying remote changes does not mark records
dirty again. `syncTransaction` is also serialized by its own lock.

`onDirty()` exposes a stream of "any dirty record exists", used for auto-sync.

## The syncChangeId incremental logic

`syncChangeId` (a.k.a. change num) is a monotonically increasing integer allocated
by the source: every `putSourceRecord` runs in a source transaction that reads meta
`lastChangeId`, increments it, stamps the record with it and writes it back to meta.

The local database stores its own progress in a **sync meta info** record
(`lastChangeId`, `lastTimestamp`, `sourceVersion`). Sync down only asks the source
for records with `syncChangeId > local lastChangeId`, which makes incremental sync
a simple ordered range query.

## Sync up (push)

`doSyncUp`:

1. Collect dirty sync records (`txnGetDirtySyncRecords`) and build the source
   records to push (`_txnGetDirtySyncSourceRecord`). This step also repairs
   inconsistencies: deleted flag set but data still present (delete the data),
   data missing but deleted flag not set (set the flag).
2. For each chunk (`stepLimitUp`, default 10), call `source.putSourceRecord` for
   each record. The **response** carries the authoritative `syncId`,
   `syncChangeId` and `syncTimestamp`.
3. In a local `syncTransaction`, for each pushed record:
   - If the local data still matches what was sent: clear `dirty`, save the sync
     info from the response, and write the response value back into the data
     store (the response is authoritative).
   - If the local data changed **during** the push (compared with
     `DeepCollectionEquality` against what was sent): keep `dirty = true` and the
     local data untouched, but save the `syncId`/`syncChangeId`/`syncTimestamp`
     from the response so the next push updates the same source record.
4. Records changed during the push are reloaded and pushed again, looping until
   nothing changes mid-push.

Note: pushing a record also bumps the source `lastChangeId`, so the client's own
pushes come back on the next sync down; they are recognized as already applied
because the local sync record already carries the response's
`syncChangeId`/`syncTimestamp`.

## Sync down (pull)

`doSyncDown`:

1. Read the local sync meta info and the source meta info.
2. Decide between **incremental** and **full** sync:
   - never synced (`lastChangeId` missing) → full sync;
   - `sourceMeta.version != local sourceVersion` → full sync from 0 (source was
     re-created / version bumped);
   - `local lastChangeId < sourceMeta.minIncrementalChangeId` → full sync
     (deleted-record history no longer available incrementally).
   - otherwise → incremental: fetch `afterChangeId = local lastChangeId` with
     `includeDeleted = true` (tombstones must be applied).
3. Fetch the records (`getAllSourceRecordList`, paged internally by
   `stepLimitDown`).
4. For a full sync, load **all** local sync records into a map keyed by
   `(store, key)`; every remote record seen removes its entry, and whatever
   remains at the end exists locally but not remotely and is deleted locally
   (unless dirty, see conflicts).
5. In a single local `syncTransaction`, for each remote record (in
   `syncChangeId` order):
   - skip invalid records and records of non-synced stores;
   - no local sync record: create the local record (skip if it is a tombstone);
   - local sync record exists and `syncTimestamp`/`syncChangeId` differ (or the
     source version changed): apply the remote record — unless a conflict, see
     below;
   - identical sync info: nothing to do.

   Applying a remote record (`_syncSourceRecordDown`) writes/deletes the data
   record and stores the remote sync info in the sync record.
6. Save the new local sync meta info (`lastChangeId` from the last record seen or
   from the fetch/meta, `lastTimestamp`, `sourceVersion`) when it changed. The
   meta is also written on a first empty sync so `lastChangeId` becomes non-null
   (0) and marks "synced at least once".
7. Complete `firstSyncDownDone` (first successful down sync signal).

## Conflict resolution

A conflict is a remote change arriving for a record that is locally dirty.

Rule: **remote wins, unless the record is dirty locally — then local wins and the
local version is pushed up — except that a remote deletion always wins.**

Concretely, during sync down:

- local record dirty + remote record changed (not deleted): the remote value is
  **not** applied; the sync record id is queued in `conflictSyncRecordIds` and,
  after the transaction, those records are pushed up via the same
  `_pushLocalDirtySourceRecords` loop as sync up (last-writer-wins at the source,
  the push allocates a newer `syncChangeId`).
- local record dirty + remote record deleted: the remote deletion is applied
  (local data is lost).
- full-sync cleanup: a local record absent from the source is deleted, unless
  dirty — then it is kept and pushed up (it becomes a create/update at the
  source).

There is no field-level merge and no timestamp comparison: conflicts are resolved
at the record level by the dirty flag.

## Concurrency and auto sync

- `syncLock` serializes `syncUp` / `syncDown` / `sync`.
- `sync()` goes through a single-flight (`SingleFlight` in the sembast version,
  `LazyRunner` in the sdb version for `lazySync`): concurrent triggers coalesce
  into one run.
- With `autoSync: true` the synchronizer listens to:
  - `streamJoin2(source.onMetaInfo(), db.onSyncMetaInfo())`: triggers a sync when
    remote and local `lastChangeId` differ (or both are 0/never synced);
  - `db.onDirty()`: triggers a sync when a local record becomes dirty.
- `close()` cancels the subscriptions and waits for a pending sync to finish.

## Statistics

Each sync returns a `SyncedSyncStat` with `local/remote` `created/updated/deleted`
counts (`local*` = applied locally by sync down, `remote*` = pushed by sync up).
`onSynced()` streams the stat after each full `sync()`.

## Known limitations of the current logic

- Conflict resolution is coarse (whole record, dirty flag only); concurrent edits
  on different fields of the same record lose one side.
- A remote deletion silently discards local dirty changes.
- Sync up performs one `putSourceRecord` round-trip per record (chunking only
  batches the local transaction, not the source writes).
- The source keeps a tombstone forever for every deleted record (until a version
  bump / `minIncrementalChangeId` purge).
- `syncChangeId` allocation serializes all writers through the source meta record
  (a transaction contention point on firestore).
