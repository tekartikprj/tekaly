## synced_db_common

Common code shared by the synchronized database implementations
(`tekaly_sembast_synced` for sembast, `tekaly_sdb_synced` for sdb/idb_shim):

- the synced source abstraction (`SyncedSource`, `SyncedSourceRead`,
  `SyncedSourceWrite`), its records and meta info models
- the in memory source (`SyncedSourceMemory`) and the firestore source
  (`SyncedSourceFirestore`)
- the tekaly export format (`SyncedDbExportInfo`, `SyncedDbExportMeta`) and
  the export/import helpers on a synced source
- the synchronizer base class (`SyncedDbSynchronizerCommon`) and its stat

The value types (`SyncedDbTimestamp`, `SyncedDbBlob`) are the sembast
`Timestamp` and `Blob` types, also used by sdb.

## Setup

`pubspec.yaml`:

```yaml
  tekaly_synced_db_common:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/synced_db_common
```
