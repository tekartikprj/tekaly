---
name: tekaly-synced-db-common-test-source-tests
description: >-
  Use when testing a custom tekaly synced source implementation (SyncedSource)
  with the shared test suites of tekaly_synced_db_common_test, or when a test
  needs an in memory or in memory firestore synced source.
---

# Synced source test suites (tekaly_synced_db_common_test)

## Guidelines

* Add `tekaly_synced_db_common_test` (and `test`) to `dev_dependencies`.
* Run `runSyncedSourceTest(createSource)` from
  `package:tekaly_synced_db_common_test/synced_source_test.dart` against any
  `SyncedSource` implementation: it checks put/get, change id increments, record
  lists, meta info and `onMetaInfo`. Pass `skipRealTimeChanges: true` when the
  source polls (no real time meta info stream).
* Also run `strictSyncedSourceTest(createSource)` when the source uses the
  `<store>|<key>` sync id format (memory, firestore, sembast sources do).
* `createSource` must return a fresh, empty source each time (the suites run
  `setUp` before every test).
* `newInMemorySyncedSourceMemory()` gives a `SyncedSourceMemory`,
  `newInMemorySyncedSourceFirestore()` (from
  `synced_source_firestore_test_common.dart`) a `SyncedSourceFirestore` on an in
  memory firestore.
* `exampleTimestamp1()` (from `synced_db_common_test_utils.dart`) is a
  timestamp safe on web (no microseconds) for synchronizer tests.

## Examples

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekaly_synced_db_common_test/synced_source_test.dart';
import 'package:test/test.dart';

import 'my_source.dart';

void main() {
  group('my_source', () {
    Future<SyncedSource> createSource() async => MySource();

    runSyncedSourceTest(createSource, skipRealTimeChanges: true);
    strictSyncedSourceTest(createSource);
  });
}
```
