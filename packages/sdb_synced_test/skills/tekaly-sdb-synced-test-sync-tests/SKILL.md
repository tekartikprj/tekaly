---
name: tekaly-sdb-synced-test-sync-tests
description: >-
  Use when testing a synced source or a synchronizer setup against an sdb
  SyncedSdb with the shared test suites of tekaly_sdb_synced_test (syncTests,
  syncedDbReadMinServiceTests, allSyncedDbTests).
---

# Synced sdb database test suites (tekaly_sdb_synced_test)

## Guidelines

* Add `tekaly_sdb_synced_test` to `dev_dependencies` (it depends on
  `tekaly_synced_db_common_test` for the source suites, no sembast needed).
* `allSyncedDbTests(setupContext)` from `synced_sdb_test_common.dart` runs
  `syncTests` (sync up/down, deletions, conflicts, multi database) and
  `syncedDbReadMinServiceTests` against a `SyncSdbTestsContext` holding a
  `SyncedSdb` and a `SyncedSource`.
* `setupContext` must return a fresh context each time. Open the database with
  the provided options: `SyncedSdb.newInMemory(options: sdbEntityOptions)`
  (store `entity`) or `sdbEntityAndLocalOptions` (plus the excluded
  `local_entity` store). `setupNewInMemorySyncSdbTestsContext()` is the ready
  made memory version.
* The suites use `sdbEntityStoreRef` / `DbEntity` (`name`, `timestamp`,
  `counter`): your source must accept the `entity` store.
* `exampleTimestamp1()` (from
  `package:tekaly_synced_db_common_test/synced_db_common_test_utils.dart`)
  gives a web safe timestamp for your own tests.

## Examples

```dart
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_synchronizer_test.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:test/test.dart';

import 'my_source.dart';

void main() {
  group('my_source_sdb_sync', () {
    Future<SyncSdbTestsContext> setupContext() async => SyncSdbTestsContext()
      ..syncedSdb = SyncedSdb.newInMemory(options: sdbEntityOptions)
      ..source = MySource();

    allSyncedDbTests(setupContext);
  });
}
```
