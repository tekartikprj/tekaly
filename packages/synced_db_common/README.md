# tekaly_synced_db_common

Common code of the tekaly synchronized databases: a local database (sdb
with `tekaly_sdb_synced`, or the legacy sembast one with
`tekaly_sembast_synced`) kept in sync with a *synced source*, a remote
change log (Firestore, memory, an api...).

- the synced source abstraction (`SyncedSource`, `SyncedSourceRead`,
  `SyncedSourceWrite`), its record and meta info models;
- the in memory source (`SyncedSourceMemory`, for tests) and the Firestore
  source (`SyncedSourceFirestore`, in `synced_db_common_firestore.dart`);
- the synchronizer base (`SyncedDbSynchronizerCommon`: sync up and down,
  auto sync, retries, sync status);
- the tekaly export format and its helpers.

Pure Dart (io, web, Flutter). An application depends on
`tekaly_sdb_synced`, which brings this package; depend on it directly to
write a source or another local database implementation.

## Getting started

```yaml
dependencies:
  tekaly_synced_db_common:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/synced_db_common
```

```dart
import 'package:tekaly_synced_db_common/synced_db_common.dart';

Future<void> main() async {
  var source = SyncedSourceMemory();
  var record = await source.putSourceRecord(
    CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = 'note'
        ..key.v = 'n1'
        ..value.v = {'title': 'Hello'}),
  );
  // Sync id note|n1, change id 1.
  print('${record.syncId.v} ${record.syncChangeId.v}');
  var changes = await source.getAllSourceRecordList(afterChangeId: 0);
  print('${changes.length} change(s), last ${changes.lastChangeId}');
  await source.close();
}
```

## How a sync works

The source numbers every change (`syncChangeId`) and keeps the last one in
its meta info (`lastChangeId`). A client pushes its dirty records, then
reads the changes after its own last change id. A client below the source
`minIncrementalChangeId` (history purged) or with another source `version`
reads every record again (full sync) and deletes the local records the
source no longer has. The details: `doc/synced_db_logic.md` and
`doc/auto_sync.md` at the repository root.

## Pitfalls

- Synced values hold `num`, `String`, `bool`, `List`, `Map`,
  `SyncedDbTimestamp` and `SyncedDbBlob` only (never `DateTime` or
  `Uint8List`), in stores with `String` keys.
- `SyncedSourceFirestore` with a partition needs a composite index
  (`record.value.<field>`, `syncChangeId`).
- Without authentication, Firestore transactions fall back to write
  batches: two writers at the same time can take the same change id.

More in the [package skill](skills/tekaly-synced-db-common-synced-source/SKILL.md).
