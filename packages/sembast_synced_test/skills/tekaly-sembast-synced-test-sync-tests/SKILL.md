---
name: tekaly-sembast-synced-test-sync-tests
description: >-
  Use when testing a synced source or a synchronizer setup against a sembast
  SyncedDb with the shared test suites of tekaly_sembast_synced_test
  (syncTests, syncedDbReadMinServiceTests, runSyncedSourceTest).
---

# Synced sembast database test suites (tekaly_sembast_synced_test)

## Guidelines

* Add `tekaly_sembast_synced_test` to `dev_dependencies` (it depends on
  `tekaly_synced_db_common_test` for the source suites).
* `syncTests(setupContext)` from `synced_db_synchronizer_test.dart` runs the
  full synchronization suite (sync up/down, deletions, conflicts, multi
  database) against a `SyncTestsContext` holding a `SyncedDb` and a
  `SyncedSource`; `syncedDbReadMinServiceTests(setupContext)` from
  `synced_db_read_min_service_test.dart` checks the read min service.
* `setupContext` must return a fresh context each time; use
  `SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)` for the database
  and your source (`newInMemorySyncedSourceMemory()`,
  `newInMemorySyncedSourceFirestore()`, `newInMemorySyncedSourceSembast()`...).
  `setupNewInMemorySyncTestsContext()` is the ready made memory version.
* The suites use the `entity` store (`dbEntityStoreRef`, `DbEntity` with
  `name`, `timestamp`, `counter`) from `synced_db_test_common.dart` and
  `entity_local` as an excluded store: your source must accept those stores.
* Put `concurrency: 1` in `dart_test.yaml` when the source is a shared
  in-process server (api, rpc).
* For the pure source suites (`runSyncedSourceTest`,
  `strictSyncedSourceTest`) see `tekaly_synced_db_common_test`.

## Examples

```dart
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_sembast_synced_test/synced_db_read_min_service_test.dart';
import 'package:tekaly_sembast_synced_test/synced_db_synchronizer_test.dart';
import 'package:test/test.dart';

import 'my_source.dart';

void main() {
  group('my_source_sync', () {
    Future<SyncTestsContext> setupContext() async => SyncTestsContext()
      ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
      ..source = MySource();

    syncTests(setupContext);
    syncedDbReadMinServiceTests(setupContext);
  });
}
```
