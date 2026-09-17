---
name: tekaly-sembast-synced-export-import
description: >-
  Use when exporting a synced sembast database (tekaly export format, jsonl)
  or importing one from memory, files, flutter assets, an http url or firebase
  storage with tekaly_sembast_synced.
---

# Export and import a synced sembast database (tekaly_sembast_synced)

A synced database can be snapshotted in the *tekaly export format*: a list of
json lines (`export.jsonl`) plus a meta json (`export_meta.json`) holding
`lastChangeId`, `lastTimestamp` and `sourceVersion`. The same format is
produced by `tekaly_sdb_synced` and by any synced source
(`source.exportInMemory()`), so a snapshot can be moved between them.

## Guidelines

* Export after a `sync()` so the meta info (`lastChangeId`) is set: an import
  only happens when the export `lastChangeId` is greater than the local one
  (or the `sourceVersion` differs).
* `syncedDb.exportInMemory()` returns a `SyncedDbExportInfo`;
  `getJsonlExport()` / `getMetaExport()` give the file contents. Export lines
  are `{"tekaly_export": 1, "version": 1}`, the meta map, then per store
  `{"store": name}` followed by `[key, value]` lines. Keys are sorted so the
  output is stable in git.
* Import from memory with `syncedDb.importFromMemory(exportInfo:)`, from a
  custom fetcher with `syncedDb.fetchAndImport(fetchExport:, fetchExportMeta:)`.
* On io (`synced_db_io.dart`): `exportDatabase(dir:)` writes `export.jsonl`
  and `export_meta.json`, `importDatabaseFromFiles(dir:)` reads them back.
* In flutter, ship the two files as assets (for example under
  `assets/data/`) and import with `importDatabaseFromAsset` from
  `synced_db_asset.dart` (a `TkAssetBundle` from
  `tekartik_app_common_utils`).
* Firebase storage (`synced_db_storage.dart`): `exportDatabaseToStorage`
  writes `export_<changeId>.jsonl` and `export_meta<suffix>.json`;
  `importDatabaseFromStorage` reads them with an authenticated storage,
  `importDatabaseFromUnauthenticatedStorage` with the public rest api
  (`UnauthenticatedStorageApi` from `tekartik_firebase_storage_rest`).
* The `*Legacy` variants (`exportInMemoryLegacy`, `fetchAndImportLegacy`,
  `importDatabaseFromFilesLegacy`) use the sembast export format; only use
  them to read old exports.
* Values are json encoded as `{"$timestamp": iso8601}` and
  `{"$blob": base64}`; do not hand craft export lines, use the api.

## Examples

### Export to files then import into a fresh database

```dart
import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/synced_db_io.dart';

Future<void> main() async {
  var syncedDb = SyncedDb.newInMemory();
  var db = await syncedDb.database;
  await stringMapStoreFactory.store('my_store').record('k').put(db, {'v': 1});
  var synchronizer = SyncedDbSynchronizer(db: syncedDb, source: SyncedSourceMemory());
  await synchronizer.sync();

  await syncedDb.exportDatabase(dir: 'export'); // export.jsonl + export_meta.json
  await synchronizer.close();
  await syncedDb.close();

  var other = SyncedDb.openDatabase(
    databaseFactory: newDatabaseFactoryMemory(),
    name: 'other.db',
  );
  await other.importDatabaseFromFiles(dir: 'export');
  print((await other.getSyncMetaInfo())!.lastChangeId.v); // 1
  await other.close();
}
```

### In memory export info

```dart
import 'package:tekaly_sembast_synced/synced_db.dart';

Future<SyncedDbExportInfo> snapshot(SyncedDb syncedDb) async {
  var exportInfo = await syncedDb.exportInMemory();
  print(exportInfo.metaInfo.lastChangeId.v);
  print(exportInfo.getJsonlExport());
  return exportInfo;
}

Future<void> restore(SyncedDb syncedDb, SyncedDbExportInfo exportInfo) =>
    syncedDb.importFromMemory(exportInfo: exportInfo);
```

### Flutter assets import

```dart
import 'package:tekaly_sembast_synced/synced_db_asset.dart';
import 'package:tekartik_app_common_utils/asset/asset_bundle.dart';

Future<void> importFromAssets(SyncedDb syncedDb, TkAssetBundle assetBundle) =>
    syncedDb.importDatabaseFromAsset(
      importContext: SyncedDbAssetImportContext(
        assetBundle: assetBundle,
        rootPath: 'assets/data',
      ),
    );
```

### Firebase storage export (server side)

```dart
import 'package:tekaly_sembast_synced/synced_db_storage.dart';
import 'package:tekartik_firebase_storage/storage.dart';

Future<void> publish(SyncedDb syncedDb, FirebaseStorage storage) async {
  var result = await syncedDb.exportDatabaseToStorage(
    exportContext: SyncedDbStorageExportContext(
      storage: storage,
      bucketName: 'my-bucket',
      rootPath: 'project/my_project/data',
    ),
  );
  print('exported ${result.exportSize} byte(s)');
}
```
