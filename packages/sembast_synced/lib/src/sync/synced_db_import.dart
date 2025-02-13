import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_synchronizer_from_export.dart';

/// Export helper
extension SyncedDbImportExt on SyncedDb {
  /// Export to memory removing meta
  Future<void> fetchAndImport({
    /// Only sync if fetch export does not return null
    required SyncedDbSynchronizerFetchExport fetchExport,

    /// Only sync if fetch export does not return null
    required SyncedDbSynchronizerFetchExportMeta fetchExportMeta,
  }) async {
    var synchronizer = SyncedDbSynchronizerFromExport(
      this,
      fetchExport: fetchExport,
      fetchExportMeta: fetchExportMeta,
    );
    await synchronizer.sync();
  }
}
