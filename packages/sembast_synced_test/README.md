# tekaly_sembast_synced_test

The shared test suites of the sembast synchronizer (`SyncedDbSynchronizer`
of `tekaly_sembast_synced`, legacy: new code uses `tekaly_sdb_synced` and
its suites, `tekaly_sdb_synced_test`): sync up and down, deletions,
conflicts, several databases on one source and the read min service, run
against any `SyncedSource`. Test code, pure Dart.

Registered here with the memory, Firestore (in memory), sembast and api
(`SyncedSourceApi` on an in memory server) sources, and by
`tekaly_sembast_synced_rpc` with its rpc source. The sembast and api sources
also run the shared source suite (`runSyncedSourceTest` of
`tekaly_synced_db_common_test`, re-exported by `synced_source_test.dart`).

## Getting started

A dev dependency, not on pub.dev:

```yaml
dev_dependencies:
  test: any
  tekaly_sembast_synced_test:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/sembast_synced_test
```

```dart
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_test/synced_db_read_min_service_test.dart';
import 'package:tekaly_sembast_synced_test/synced_db_synchronizer_test.dart';
import 'package:test/test.dart';

void main() {
  group('my_source', () {
    // A new database and a new, empty source for each test.
    Future<SyncTestsContext> setupContext() async => SyncTestsContext()
      ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
      ..source = SyncedSourceMemory(); // your source

    syncTests(setupContext);
    syncedDbReadMinServiceTests(setupContext);
  });
}
```

The suites write to the `entity` store (`dbEntityStoreRef`, `DbEntity` of
`synced_db_test_common.dart`): your source must accept it. Keep
`concurrency: 1` in `dart_test.yaml` for a source that is a shared in process
server (api, rpc).

Package skill (for AI coding agents, `skills/`):
`tekaly-sembast-synced-test-sync-tests`.
