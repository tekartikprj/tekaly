---
name: tekaly-sdb-synced-export-import
description: >-
  Use when exporting a synced sdb database to the tekaly export format (jsonl
  string, memory, files, Firebase Storage with cache headers) or importing
  one, with tekaly_sdb_synced: exportInMemory, exportToJsonlString,
  exportDatabase, exportDatabaseToStorage, SyncedSdbStorageExportContext,
  SyncedSdbSynchronizerFromTekalyExport, fetchAndImport.
---

# Export and import a synced sdb database (tekaly_sdb_synced)

The tekaly export format (`export.jsonl` + `export_meta.json`) is shared with
`tekaly_sembast_synced` and with synced sources (`source.exportInMemory()`):
an export made by one can be imported by any other.

## Guidelines

* Export after a `sync()` so `lastChangeId` is set; an import is applied only
  when the export `lastChangeId` is greater than the local one or the
  `sourceVersion` differs. An import is a snapshot: records missing from the
  export are deleted locally, and so are the records of a synced store the
  export does not list (an export never lists a store without records).
  `local_` and system stores are left alone.
* `syncedSdb.exportInMemory()` returns a `SyncedDbExportInfo` (`metaInfo`,
  `data` lines); `exportToJsonlString()` / `importFromJsonlString(jsonl)` work
  with a single jsonl string. `importFromMemory(exportInfo:)` and
  `fetchAndImport(fetchExport:, fetchExportMeta:)` import from memory or a
  custom fetcher.
* Only non system, non `local_` stores are exported
  (`syncedSdbExportableStoreNames(db)`); the stores must exist in the local
  schema to be imported.
* On io (`synced_sdb_io.dart`): `exportDatabase(dir:)` writes
  `export.jsonl` and `export_meta.json`, `importDatabaseFromFiles(dir:)`
  reads them.
* On Storage (`synced_sdb_storage.dart`), to publish a database to many
  readers: `exportDatabaseToStorage(exportContext:
  SyncedSdbStorageExportContext(storage:, rootPath:))` writes
  `<rootPath>/export_<changeId>.jsonl` (public, immutable cache control) then
  `<rootPath>/export_meta.json` (`no-cache`), so a reader never gets a meta
  pointing to a missing file. It writes nothing when the published meta
  already has the database change id (`result.written` is false). The change
  id only moves on a sync: publish a synced mirror of the source, local
  changes are not published before the next sync. Pass
  `exportCacheControl: null` (and `metaCacheControl: null`) for an export
  that is not public. Readers use `SyncedSdbSynchronizerFromTekalyExport(db,
  fetchExport: context.fetchExport, fetchExportMeta:
  context.fetchExportMeta)` or their own http fetchers on the same files.
* Values are json encoded as `{"$timestamp": iso8601}` and
  `{"$blob": base64}` (`sdbValueToJsonEncodable`), map keys are sorted so the
  files are stable in git.

## Examples

```dart
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_io.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';

final myStore = SdbStoreRef<String, SdbModel>('my_store');
final schema = SdbDatabaseSchema(
  stores: [myStore.schema(), ...syncedSdbMetaSchema.stores],
);
SyncedSdbOptions newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: schema),
);

Future<void> main() async {
  var syncedSdb = SyncedSdb.newInMemory(options: newOptions());
  var db = await syncedSdb.database;
  await myStore.record('k').put(db, {'v': 1, 'ts': SdbTimestamp(1, 2000)});
  var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: SyncedSourceMemory());
  await synchronizer.sync();

  // Files
  await syncedSdb.exportDatabase(dir: 'export');
  // Or a string
  var jsonl = await syncedSdb.exportToJsonlString();
  await synchronizer.close();
  await syncedSdb.close();

  var other = SyncedSdb.newInMemory(options: newOptions());
  await other.importDatabaseFromFiles(dir: 'export');
  // or: await other.importFromJsonlString(jsonl);
  print(await myStore.record('k').getValue(await other.database));
  await other.close();
}
```

### Publish to Storage, read back as an audience

```dart
import 'package:tekaly_sdb_synced/synced_sdb_storage.dart';
import 'package:tekartik_firebase_storage/storage.dart';

/// [server] is a synced mirror of the source, [audience] an empty local db
/// with the same schema.
Future<void> publishAndRead(
  Storage storage,
  SyncedSdb server,
  SyncedSdb audience,
) async {
  var exportContext = SyncedSdbStorageExportContext(
    storage: storage,
    rootPath: 'published/my_project',
  );
  var result = await server.exportDatabaseToStorage(
    exportContext: exportContext,
  );
  print('published ${result.changeId}, written: ${result.written}');

  await SyncedSdbSynchronizerFromTekalyExport(
    audience,
    fetchExport: exportContext.fetchExport,
    fetchExportMeta: exportContext.fetchExportMeta,
  ).sync();
}
```
