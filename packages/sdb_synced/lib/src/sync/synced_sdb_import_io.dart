import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb_export.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb_import.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';

/// Imports a synced database snapshot from local IO files.
extension SyncedSdbImportIoExt on SyncedSdb {
  /// Imports a database snapshot from files written by
  /// [SyncedSdbExportIoExt.exportDatabase].
  Future<void> importDatabaseFromFiles({
    /// Directory containing `export.jsonl` and `export_meta.json`.
    required String dir,
  }) async {
    await fetchAndImport(
      fetchExport: (int changeId) async {
        var file = File(join(dir, syncedSdbExportFilename));
        return file.readAsString();
      },
      fetchExportMeta: () async {
        var fileMeta = File(join(dir, syncedSdbExportMetaFilename));
        var map = jsonDecode(await fileMeta.readAsString()) as Map;
        return map.cast<String, Object?>();
      },
    );
  }
}
