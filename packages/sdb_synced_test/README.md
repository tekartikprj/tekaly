# tekaly_sdb_synced_test

The shared test suites of the sdb synchronizer (`SyncedSdbSynchronizer` of
`tekaly_sdb_synced`): sync up and down, deletions, conflicts, several
databases on one source, the read min service and partitioned sources, run
against any `SyncedSource`. Test code, pure Dart.

Registered here with the memory source and the Firestore source (in memory).
The source suites themselves (`runSyncedSourceTest`) live in
`tekaly_synced_db_common_test`; the sembast twin of these suites is
`tekaly_sembast_synced_test` (legacy, new code uses sdb).

## Getting started

A dev dependency, not on pub.dev:

```yaml
dev_dependencies:
  test: any
  tekaly_sdb_synced_test:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/sdb_synced_test
```

```dart
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_synchronizer_test.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:test/test.dart';

void main() {
  group('my_source', () {
    // A new database and a new, empty source for each test.
    Future<SyncSdbTestsContext> setupContext() async => SyncSdbTestsContext()
      ..syncedSdb = SyncedSdb.newInMemory(options: sdbEntityOptions)
      ..source = SyncedSourceMemory(); // your source

    allSyncedDbTests(setupContext);
  });
}
```

- `allSyncedDbTests(setupContext)` = `syncTests` (the synchronizer suite)
  + `syncedDbReadMinServiceTests`.
- `syncedSdbPartitionTests(createPartitionedSource)` for a source read by
  partition (`synced_sdb_partition_test.dart`).
- The suites write to the `entity` store (`sdbEntityStoreRef`, `DbEntity`)
  and use `local_entity` as a local store: your source must accept them.
- Keep `concurrency: 1` in `dart_test.yaml` for a source that is a shared in
  process server.

Package skill (for AI coding agents, `skills/`):
`tekaly-sdb-synced-test-sync-tests`.
