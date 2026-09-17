---
name: tekaly-sdb-synced-export-import
description: >-
  Use when exporting a synced sdb database to the tekaly export format (jsonl
  string, memory, files) or importing one, with tekaly_sdb_synced.
---

# Export and import a synced sdb database (tekaly_sdb_synced)

The tekaly export format (`export.jsonl` + `export_meta.json`) is shared with
`tekaly_sembast_synced` and with synced sources (`source.exportInMemory()`):
an export made by one can be imported by any other.

## Guidelines

* Export after a `sync()` so `lastChangeId` is set; an import is applied only
  when the export `lastChangeId` is greater than the local one or the
  `sourceVersion` differs. Records missing from the export are deleted
  locally (an import is a snapshot).
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
