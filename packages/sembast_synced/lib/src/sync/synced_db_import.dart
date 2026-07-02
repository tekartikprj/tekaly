import 'dart:convert';

import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_synchronizer_from_export_legacy.dart';

import 'synced_db_synchronizer_from_export.dart';

/// Export helper
extension SyncedDbImportExt on SyncedDb {
  /// Export to memory removing meta
  Future<void> fetchAndImportLegacy({
    /// Only sync if fetch export does not return null
    required SyncedDbSynchronizerFetchExport fetchExport,

    /// Only sync if fetch export does not return null
    required SyncedDbSynchronizerFetchExportMeta fetchExportMeta,
  }) async {
    var synchronizer = SyncedDbSynchronizerFromExportLegacy(
      this,
      fetchExport: fetchExport,
      fetchExportMeta: fetchExportMeta,
    );
    await synchronizer.sync();
  }

  /// Imports a database snapshot from files written by [exportDatabase].
  Future<void> importFromMemoryLegacy({
    /// Directory containing `export.jsonl` and `export_meta.json`.
    required SyncedDbExportInfo exportInfo,
  }) async {
    await fetchAndImportLegacy(
      fetchExport: (int changeId) async {
        //print(exportInfo.data);
        return exportInfo.data.map((line) => jsonEncode(line)).join('\n');
      },
      fetchExportMeta: () async {
        return exportInfo.metaInfo.toMap();
      },
    );
  }

  /// Export to memory removing meta
  Future<void> fetchAndImport({
    /// Only sync if fetch export does not return null
    required SyncedDbSynchronizerFetchExport fetchExport,

    /// Only sync if fetch export does not return null
    required SyncedDbSynchronizerFetchExportMeta fetchExportMeta,
  }) async {
    var synchronizer = SyncedDbSynchronizerFromTekalyExport(
      this,
      fetchExport: fetchExport,
      fetchExportMeta: fetchExportMeta,
    );
    await synchronizer.sync();
  }

  /// Imports a database snapshot from files written by [exportDatabase].
  Future<void> importFromMemory({
    /// Directory containing `export.jsonl` and `export_meta.json`.
    required SyncedDbExportInfo exportInfo,
  }) async {
    await fetchAndImport(
      fetchExport: (int changeId) async {
        return exportInfo.data.map((line) => jsonEncode(line)).join('\n');
      },
      fetchExportMeta: () async {
        return exportInfo.metaInfo.toMap();
      },
    );
  }
}
