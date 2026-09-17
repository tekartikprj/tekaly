---
name: tekaly-synced-db-common-synced-source
description: >-
  Use when implementing or consuming a tekaly synced source (SyncedSource,
  SyncedSourceRead, SyncedSourceWrite), its records (CvSyncedSourceRecord,
  CvMetaInfo) or the tekaly export format shared by tekaly_sembast_synced and
  tekaly_sdb_synced.
---

# Synced source (tekaly_synced_db_common)

`tekaly_synced_db_common` is the database agnostic layer shared by
`tekaly_sembast_synced` (sembast local database) and `tekaly_sdb_synced`
(sdb/idb_shim local database). It defines the *synced source*: a dumb remote
change log a local database synchronizes with.

## Guidelines

* Import `package:tekaly_synced_db_common/synced_db_common.dart`. Add
  `synced_db_common_firestore.dart` only when using `SyncedSourceFirestore`.
* A source is a change log, not a snapshot store: `putSourceRecord` assigns a
  `syncId` (`<store>|<key>` when new), the next incremental `syncChangeId` and a
  server `syncTimestamp`, and bumps the meta `lastChangeId`. The returned record
  is authoritative.
* Records are `CvSyncedSourceRecord` (cv models). The data is in
  `record.v` (`CvSyncedSourceRecordData`: `store`, `key`, `value`, `deleted`).
  A deleted record has `deleted.v == true` or a null `value`.
* Only stores with `String` keys and `Map<String, Object?>` values are synced.
  Values are made of `num`, `String`, `bool`, `List`, `Map`, `SyncedDbTimestamp`
  and `SyncedDbBlob` (the sembast `Timestamp`/`Blob` types, also used by sdb).
  Never put `DateTime` or `Uint8List` in a synced value.
* Implement a read-only source with `SyncedSourceReadDefaultMixin` +
  `SyncedSourceRead`, a write-only one with `SyncedSourceWriteDefaultMixin` +
  `SyncedSourceWrite`, a read-write one with `SyncedSourceDefaultMixin` +
  `SyncedSource`. Call `initBuilders()` in the constructor. Override
  `getMetaInfo`, `getSourceRecord`, `getSourceRecordList`, `putSourceRecord`
  (and `onMetaInfo` when real time changes are available, the default polls
  every hour).
* `getSourceRecordList(afterChangeId:, limit:, includeDeleted:)` returns
  records with `syncChangeId > afterChangeId` ordered by change id;
  `SyncedSourceRecordList.lastChangeId` is the last change id *read* (deleted
  included) so the caller can resume. Use `getAllSourceRecordList` (extension)
  to page through everything.
* `putMetaInfo` must reject a `minIncrementalChangeId` lower than the existing
  one (throw `StateError`). Bump `version` to force every client to resync.
* Use `SyncedSourceMemory` in tests and as a reference implementation. Use
  `SyncedSourceFirestore(firestore:, rootPath:)` for firestore (`data` and
  `meta/info` under `rootPath`).
* Export format: `source.exportInMemory()` gives a `SyncedDbExportInfo`
  (`metaInfo` + `data` lines) identical to what a synced sembast or sdb
  database exports; `source.importFromMemory(exportInfo:)` pushes every record
  as a new change. Values are json encoded with
  `syncedDbValueToJsonEncodable` (`{"$timestamp": iso}`, `{"$blob": base64}`).
* Testing: `SyncedSourceMemory` fails on purpose through
  `source.failureControl.fail(error:, duration:, count:, operations:)` /
  `.stop()` (a `SyncedSourceFailureException` by default, every
  `SyncedSourceOperation` unless restricted). Use it to check that a
  synchronizer retries while the source is unreachable.
* `SyncedDbSynchronizerCommon` retries a failed synchronization in auto sync
  mode, driven by `SyncedDbSynchronizerRetryOptions(firstSyncDelay: 5s,
  firstSyncShortDuration: 1mn, firstSyncMaxDelayDuration: 5mn, delay: 15s,
  maxDelay: 1mn, backoffFactor: 2)`. While `isFirstSyncDone` is false the
  delay is time based (`retryingFor`): `firstSyncDelay` during
  `firstSyncShortDuration`, then growing linearly to `maxDelay` at
  `firstSyncMaxDelayDuration`. Once it is done it is count based: `delay`
  multiplied by `backoffFactor` per consecutive failure, capped at `maxDelay`.
  Everything resets on success. `firstSyncDownDone()` completes on the first
  successful sync down, `onSyncError()` streams the failures, `.noRetry()`
  disables retrying.
* `debugSyncedDbSynchronizer = true` prints the synchronization steps (dev
  only, `@doNotSubmit`).
* Extend `SyncedDbSynchronizerCommon` only when writing a new local database
  implementation; applications use `SyncedDbSynchronizer` (sembast) or
  `SyncedSdbSynchronizer` (sdb).

## Examples

### Writing and reading records on a source

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';

Future<void> main() async {
  var source = SyncedSourceMemory();

  var record = await source.putSourceRecord(
    CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = 'entity'
        ..key.v = 'a1'
        ..value.v = {'name': 'test', 'timestamp': SyncedDbTimestamp(2, 3000)}),
  );
  print(record.syncId.v); // entity|a1
  print(record.syncChangeId.v); // 1

  // Read by store/key (sync id optional)
  var read = await source.getSourceRecord(
    SyncedDataSourceRef(store: 'entity', key: 'a1'),
  );
  print(read!.record.v!.value.v);

  // Changes after change id 0, deleted ones included
  var list = await source.getAllSourceRecordList(
    afterChangeId: 0,
    includeDeleted: true,
  );
  print('${list.length} change(s), last ${list.lastChangeId}');

  // Delete: a record without value, deleted flag set
  await source.putSourceRecord(
    CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = 'entity'
        ..key.v = 'a1'
        ..deleted.v = true),
  );
  await source.close();
}
```

### Implementing a read-only source wrapping another one

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';

class ReadOnlySource
    with SyncedSourceReadDefaultMixin
    implements SyncedSourceRead {
  final SyncedSource inner;

  ReadOnlySource(this.inner) {
    initBuilders();
  }

  @override
  Future<CvMetaInfo?> getMetaInfo() => inner.getMetaInfo();

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef) =>
      inner.getSourceRecord(sourceRef);

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) => inner.getSourceRecordList(
    afterChangeId: afterChangeId,
    limit: limit,
    includeDeleted: includeDeleted,
  );

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) =>
      inner.onMetaInfo(checkDelay: checkDelay);
}
```

### Checking that a synchronizer retries an unreachable source

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';

Future<void> testRetry(SyncedDbSynchronizerCommon Function(SyncedSource) open) async {
  var source = SyncedSourceMemory();
  // The source is down when the database opens.
  source.failureControl.fail();
  var synchronizer = open(source); // built with autoSync: true
  await Future<void>.delayed(const Duration(seconds: 1));
  print(synchronizer.isFirstSyncDone); // false, but it keeps retrying
  print(synchronizer.consecutiveSyncFailureCount); // > 1

  // The source is back: the next retry succeeds, no need to sync by hand.
  source.failureControl.stop();
  await synchronizer.firstSyncDownDone();
}
```

### Export / import between sources

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';

Future<void> copy(SyncedSourceRead from, SyncedSourceWrite to) async {
  var exportInfo = await from.exportInMemory();
  // exportInfo.data: [{'tekaly_export': 1, 'version': 1}, {meta}, {'store': ..}, [key, value], ...]
  await to.importFromMemory(exportInfo: exportInfo);
  print(exportInfo.getJsonlExport()); // one json line per item
}
```
