# Firestore auto sync: sync state and initial synchronization

Status: **phases 1 and 2 implemented** (2026-09-28), phase 3 open, see
[Implementation](#implementation).

Scope: `AutoSynchronizedFirestoreSyncedSdb` / `AutoSynchronizedFirestoreSyncedDb`
(shared implementation `AutoSynchronizedFirestoreSyncedDbBase` in
`packages/synced_db_common/lib/src/auto_synced_firestore.dart`) and the
synchronizer they drive in auto sync mode (`SyncedDbSynchronizerCommon` /
`SyncedDbSynchronizerBase`). The sync algorithm itself is described in
[synced_db_logic.md](synced_db_logic.md).

## Goal

- Expose a **state of the auto sync**: at least "never done" vs "initial sync
  done", plus what is going on (syncing, failing, waiting for a retry).
- **Retry the initial sync automatically** when it fails (after a delay, etc.).
- Let the **app decide** not to display any data until the initial sync is
  done, without hand-written timeouts, and show something meaningful while it
  waits (offline, retrying...).

## Before this work

### Two different "initial sync done" signals

| Signal | Where | Meaning | Persisted |
|---|---|---|---|
| `initialSynchronizationDone()` | `SyncedSdb` / `SyncedDb` (mixins), forwarded by the auto synced db | the local sync meta info has a non-null `lastChangeId`: a sync down succeeded **once, in this or a previous session** | yes (local meta info) |
| `firstSyncDownDone()` / `isFirstSyncDone` | `SyncedDbSynchronizerCommon` | a sync down succeeded **in this session** (this synchronizer instance) | no |

On an app restart with a database synced in a previous session,
`initialSynchronizationDone()` resolves immediately (even offline, even if the
data is days old), while `firstSyncDownDone()` waits for the network. On a first
run offline, both never complete.

The local meta info is only written by a successful sync down: the first one
writes `lastChangeId` (0 for an empty source). A firestore read answered from
the client cache (web/mobile offline) throws `SyncedSourceOfflineException`
(2556b91), so a cached answer can never mark the initial sync as done.

### Retry was already implemented

`SyncedDbSynchronizerRetryOptions`
(`packages/synced_db_common/lib/src/synced_db_synchronizer_retry.dart`,
b4a01f3 and 5064805), passed through
`AutoSynchronizedFirestore...Options.retryOptions`:

| Phase | Default delay between retries |
|---|---|
| First sync not done yet, first minute of retrying | 5s (`firstSyncDelay`, `firstSyncShortDuration`) |
| First sync not done yet, 1 to 5 minutes of retrying | growing linearly from 5s to 1mn (`firstSyncMaxDelayDuration`, `maxDelay`) |
| First sync done | 15s, doubled on each consecutive failure up to 1mn (`delay`, `backoffFactor`, `maxDelay`) |
| After a permanent error (added by this work) | 1mn (`permanentErrorDelay`) |

- Any success resets the counters and cancels the pending retry.
- `SyncedDbSynchronizerRetryOptions.noRetry()` disables it.
- An error of the source meta info stream (`onMetaInfo`) counts as a failure,
  so an unreachable source starts the retries.
- A **first sync watchdog** triggers a sync after `firstSyncDelay` when nothing
  happened at all (a source that neither answers nor fails).
- Errors are published on `synchronizer.onSyncError()`.

### What triggers a sync in auto sync mode

- The source and local meta info `lastChangeId` differ (or are both 0).
- A local record becomes dirty (read-write only).
- A scheduled retry, the first sync watchdog.
- An explicit `synchronize()` / `lazySynchronize()` / `requestSync()` from the
  app.

### How apps coped

Apps awaited `initialSynchronizationDone()`, typically wrapped in an
`initialSyncDone()` helper documented as "may never complete while offline on
a first run", some with a hand-written timeout (10 to 20s) after which the
local data is shown "as it is (offline)". tkcms
(`firestore_synced_entities_db.dart`) awaits it right after `open`.

### Gaps

1. **No observable state**: only futures. An app could not show "offline, retry
   in 5s", "last synced ...", or "changes waiting to be sent".
2. **No way to tell "never synced" from "synced in a previous session"**
   without awaiting with a timeout, and nothing to require data fresh from
   this session.
3. **Waits never ended**: on a first run offline, and on close
   (`SyncedSdb.close()` closes the meta info subject, a pending
   `initialSynchronizationDone()` fails with a `StateError`; the sembast
   `onRecord` stream may just stay open).
4. **No "retry now"** without awaiting `synchronize()`, which throws.
5. **All errors retried the same way**: `permission-denied` every 5s like a
   network error.
6. **A failing push blocked the pull**: `doSync` runs `doSyncUp` then
   `doSyncDown`; a local change rejected by the rules made every sync fail
   before pulling, so on a first run the initial sync never completed.
7. **A hung sync is never retried** (still open, see phase 3).

## Design (implemented)

### State model

Two independent dimensions, in one immutable `SyncedDbSyncStatus` snapshot.

**`SyncedDbInitialSync`**, how fresh the local data is:

| Value | Meaning | Source of truth |
|---|---|---|
| `unknown` | local meta info not read yet (a few ms at start) | - |
| `never` | never synchronized: the local db only holds local changes, if any | local meta `lastChangeId == null` |
| `previousSession` | synchronized before, not yet in this session: possibly stale | local meta `lastChangeId != null`, no sync down this session |
| `thisSession` | a sync down succeeded in this session | a successful sync down (`markFirstSyncDone`) |

**`SyncedDbSyncActivity`**, what the synchronizer is doing:

| Value | Meaning |
|---|---|
| `idle` | nothing running, the last sync (if any) succeeded |
| `syncing` | a sync (`sync()`, auto sync, retry) is running |
| `retryScheduled` | the last sync failed with a transient error, a retry is scheduled (`nextRetryTime`) |
| `failed` | the last sync failed with a permanent error (a slow retry is still scheduled in auto sync mode, after `permanentErrorDelay`), or retrying is off (no auto sync, `noRetry`) |
| `closed` | closed, the status stream is done |

```
                open
                  |
             [unknown] --local meta read--> [never] or [previousSession]
                                                 |
   any state --sync down succeeds--> [thisSession]   (kept until closed)

   activity:  idle --trigger--> syncing --ok--> idle
                                  |
                                  +--transient error--> retryScheduled --timer / requestSync--> syncing
                                  +--permanent error / no retry--> failed --slow timer / trigger / requestSync--> syncing
              any --close--> closed
```

`SyncedDbSyncStatus` also carries `readOnly`, `hasLocalChanges` (always false
when read-only), `lastSyncTime` (last successful sync down this session),
`lastError`, `failureCount`, `retryingSince` and `nextRetryTime` (UTC times).

### API

Synchronizer (`SyncedDbSynchronizerCommon`):

```dart
SyncedDbSyncStatus get syncStatus;
Stream<SyncedDbSyncStatus> onSyncStatus(); // current value first, then changes
Future<SyncedDbSyncStatus> waitInitialSync({
  SyncedDbInitialSyncPolicy policy = SyncedDbInitialSyncPolicy.any,
  Duration? timeout,
});
void requestSync();
```

Auto synced firestore db (`AutoSynchronizedFirestoreSyncedDbCommon`, both the
sdb and sembast ones): `onSyncStatus()`, `waitInitialSync()`, `requestSync()`,
and `initialSynchronizationDone()` now built on `waitInitialSync()`: it
throws a `StateError` when closed before the initial sync instead of hanging.

Policies (`SyncedDbInitialSyncPolicy`), checked by
`SyncedDbSyncStatus.satisfies`:

| Policy | Satisfied when |
|---|---|
| `none` | always (local first) |
| `any` | `previousSession` or `thisSession` (the `initialSynchronizationDone()` behaviour) |
| `thisSession` | `thisSession` (fresh data required) |

`waitInitialSync` completes with the status satisfying the policy, or with the
current one when closed or when `timeout` expires: it never hangs with a
timeout and never throws, the caller checks the returned status.

Tracking starts on creation in auto sync mode, otherwise when the status is
first requested. The status is a stream: its first values can precede the
reading of the local meta info and dirty records (`unknown`,
`hasLocalChanges: false` for a few ms), listeners wait for what they need.

### Errors and retry

- `isSyncedSourcePermanentError(error)` (`synced_source_error.dart`): a
  `SyncedSourcePermanentException`, or a firestore error code among
  `permission-denied`, `unauthenticated`, `invalid-argument`,
  `failed-precondition`, `unimplemented`. The code is read from a
  `FirestoreException` (rest, sim) or from the text of a flutter
  `FirebaseException` (`[cloud_firestore/permission-denied] ...`), so no
  flutter dependency is needed. Anything else (network, `unavailable`,
  `SyncedSourceOfflineException`...) is transient.
- A permanent error gives the `failed` activity and a retry after
  `permanentErrorDelay` (1mn by default) instead of the fast schedule. Any
  trigger (source or local change, `requestSync()`) still syncs right away,
  for example after a sign in.
- **The pull is done even if the push fails permanently**: `doSync` catches a
  permanent `doSyncUp` error, runs `doSyncDown`, then throws the push error
  (the records stay dirty, the sync counts as failed). A transient push error
  still aborts the whole sync, since the pull would fail too.
- The sync down marks the first sync as done right after its local
  transaction, before pushing the conflicting records (local wins), so a
  failing conflict push no longer prevents the initial sync.
- `requestSync()`: fire-and-forget, cancels the scheduled retry and triggers a
  sync; errors go to `onSyncError()` and the status, they are not thrown.

### App usage

Suggested UI per status, the policy deciding when data is shown:

| Initial sync | Activity | Suggested UI |
|---|---|---|
| `unknown` | any | splash (few ms) |
| `never` | `syncing` | full screen loading |
| `never` | `retryScheduled` | "Can't reach the server, retrying..." (`nextRetryTime`) + Retry (`requestSync`); optionally "Continue offline" when the app lets the user create data locally |
| `never` | `failed` | error with the reason (`lastError`, e.g. no access) + Retry |
| `previousSession` | `syncing` | data + discreet syncing indicator (`thisSession` policy: loading + "Show offline data") |
| `previousSession` | `retryScheduled` | data + "Offline" banner |
| `thisSession` | `idle` | data |
| `thisSession` | `retryScheduled` / `failed` | data + offline/error banner, "changes waiting to be sent" when `hasLocalChanges` |

Riverpod sketch, replacing an `initialSynchronizationDone().timeout(...)`:

```dart
final syncStatusProvider = StreamProvider.autoDispose
    .family<SyncedDbSyncStatus, String>((ref, id) async* {
      var db = await ref.watch(autoSyncedDbProvider(id).future);
      yield* db.onSyncStatus();
    });

// In the page: show the data once
// status.satisfies(SyncedDbInitialSyncPolicy.any), else the waiting/retry
// screen driven by status.activity / status.nextRetryTime, with a Retry
// button calling db.requestSync().
```

"Continue offline" on a never synced db works with the current logic: local
records are created dirty, and the first sync (a full sync) keeps the dirty
records that do not exist remotely and pushes them.

## Edge cases

- **First run offline**: `never` + `retryScheduled`, retries every 5s for a
  minute, then slower. `waitInitialSync(timeout:)` hands the decision back to
  the app.
- **Firestore cache (web/mobile offline)**: `SyncedSourceOfflineException`, a
  transient failure, never reaches `thisSession` from the cache.
- **Offline restart after a previous sync**: `previousSession` as soon as the
  local meta info is read; `any` policy satisfied, `thisSession` not.
- **Source version bump / `minIncrementalChangeId`**: full re-sync, local data
  kept until replaced; not an initial sync (no going back to `never`).
- **Local sync info cleared** (test only `clearAllSyncInfo`): once
  `thisSession` is reached it is kept until closed; before that the status
  follows the local meta info stream (the sdb stream only reports what is read
  or written through `getSyncMetaInfo` / `setSyncMetaInfo`).
- **Close while waiting**: activity `closed`, `waitInitialSync` completes with
  it, the auto synced `initialSynchronizationDone()` throws a `StateError`.
  The db level `SyncedSdb` / `SyncedDb.initialSynchronizationDone()` are
  unchanged.
- **Read-only**: same states, `hasLocalChanges` always false.
- **Several dbs**: one status each, aggregated by the app if needed.

## Compatibility

- Additive: `initialSynchronizationDone()`, `firstSyncDownDone()`,
  `isFirstSyncDone`, `onSyncError()`, `synchronize()`, `lazySynchronize()` and
  the retry options keep their behaviour, except:
  - the auto synced `initialSynchronizationDone()` throws on close instead of
    hanging (sembast) or failing with a no element `StateError` (sdb);
  - a permanent error is retried after 1mn instead of 5s/15s;
  - a permanently failing push no longer prevents the pull.
- New exports from `tekaly_sdb_synced/synced_sdb.dart` and
  `tekaly_sembast_synced/synced_db.dart`: `SyncedDbSyncStatus`,
  `SyncedDbInitialSync`, `SyncedDbSyncActivity`, `SyncedDbInitialSyncPolicy`,
  `SyncedSourcePermanentException`, `isSyncedSourcePermanentError`; and
  `SyncedSourceOfflineException` from the firestore libraries.

## Implementation

1. **Status** (done): `synced_db_sync_status.dart`, status tracking in
   `SyncedDbSynchronizerCommon` (activity from the single flight and the retry
   timer) and `SyncedDbSynchronizerBase` (local meta info, dirty records,
   `localHasDirtySyncRecords` hook), forwarded by the auto synced db.
   Tests: `synced_db_common_test/test/synced_db_sync_status_test.dart` (sdb and
   sembast, `SyncedSourceMemory` failure injection) and
   `synced_db_common/test/synced_db_sync_status_test.dart`.
2. **Retry now and errors** (done): `requestSync()`,
   `isSyncedSourcePermanentError`, `permanentErrorDelay`, `failed` activity,
   pull when the push fails permanently, first sync marked before the conflict
   push.
3. **Open**: persisted last sync time in the local meta info ("last synced ..."
   across sessions, staleness policy), connectivity hint (`Stream<bool>` in the
   options: retry when back online, pause retries offline), per-attempt
   timeout for a hung sync (the request cannot be cancelled and holds
   `syncLock`).
4. **Apps**: adopt `onSyncStatus` / `waitInitialSync` where hand-written
   timeouts or never completing waits are used (tkcms, festenao...).

## Open questions

- Per-attempt timeout: default value, and how to let the next attempt proceed
  while a hung one still holds the lock.
- Should `requestSync()` reset the backoff when it fails? (It currently counts
  as a regular failure.)
- Should the status also live on the synced db (without a synchronizer), for a
  db synchronized manually?
