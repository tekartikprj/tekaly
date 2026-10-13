// ignore_for_file: public_member_api_docs

import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/src/export/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';

import 'synced_db_down_synchronizer.dart';
import 'synced_db_import_merge.dart';

/// Sync from export
class SyncedDbSynchronizerFromTekalyExport
    with SyncedDbDownSynchronizerMixin
    implements SyncedDbDownSynchronizer {
  SyncedDbSynchronizerFromTekalyExport(
    SyncedDb db, {
    required this.fetchExport,
    required this.fetchExportMeta,
  }) {
    this.db = db;
  }

  /// Only sync if fetch export does not return null
  final SyncedDbSynchronizerFetchExport fetchExport;

  /// Only sync if fetch export does not return null
  final SyncedDbSynchronizerFetchExportMeta fetchExportMeta;

  @override
  Future<void> sync() async {
    var meta = await db.getSyncMetaInfo();
    var newMeta = SyncedDbExportMeta()..fromMap(await fetchExportMeta());
    var newLastChangeId = newMeta.lastChangeId.v!;
    if ((meta?.sourceVersion.v != newMeta.sourceVersion.v) ||
        (newMeta.lastChangeId.v! > (meta?.lastChangeId.v ?? 0))) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('importing data $newMeta');
      }

      var data = await fetchExport(newLastChangeId);

      var sourceDb = await tekalyToSembastImportDatabaseAny(
        data,
        newDatabaseFactoryMemory(),
        'export',
      );
      try {
        await syncedDbImportSourceDatabase(
          db,
          sourceDatabase: sourceDb,
          exportMeta: newMeta,
        );
      } finally {
        await sourceDb.close();
      }
    }
  }
}
