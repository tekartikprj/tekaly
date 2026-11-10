# tekaly_synced_db_common_test

The shared test suites of the tekaly synced sources (`SyncedSource` of
`tekaly_synced_db_common`): every source implementation runs the same tests,
so a behaviour fixed in one is checked in all of them. Also in memory sources
for tests. Pure Dart.

Registered today by the memory sources and the Firestore source (here), the
sembast source (`tekaly_sembast_synced_test`) and the rpc source
(`tekaly_sembast_synced_rpc`).

## Getting started

A dev dependency, not on pub.dev:

```yaml
dev_dependencies:
  test: any
  tekaly_synced_db_common_test:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/synced_db_common_test
```

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekaly_synced_db_common_test/synced_source_test.dart';
import 'package:test/test.dart';

void main() {
  group('my_source', () {
    // A new, empty source for each test.
    Future<SyncedSource> createSource() async => SyncedSourceMemory();

    runSyncedSourceTest(createSource, skipRealTimeChanges: true);
    strictSyncedSourceTest(createSource);
  });
}
```

## The suites

- `runSyncedSourceTest(createSource, {skipRealTimeChanges})`: put and get
  (change ids, sync ids, every value type, an update dropping fields),
  record lists and paging past pages of deleted records, the meta info (a
  `putMetaInfo` keeps the fields it does not set, `minIncrementalChangeId`
  never goes back), `onMetaInfo`. `skipRealTimeChanges: true` for a source
  whose `onMetaInfo` polls.
- `strictSyncedSourceTest(createSource)`: the `<store>|<key>` sync id and the
  stored record format (memory, Firestore, sembast sources).
- `runSyncedSourcePartitionTest(createPartitionedSource)`: a source read by
  partition (a user id field).
- `newInMemorySyncedSourceMemory()`, `newInMemorySyncedSourceFirestore()`
  (`synced_source_firestore_test_common.dart`, a Firestore in memory) and
  `exampleTimestamp1()` (`synced_db_common_test_utils.dart`, no microseconds
  for the web).

The synchronizer suites (sync up and down against each source) live in
`tekaly_sdb_synced_test` and `tekaly_sembast_synced_test`.

Package skill (for AI coding agents, `skills/`):
`tekaly-synced-db-common-test-source-tests`.
