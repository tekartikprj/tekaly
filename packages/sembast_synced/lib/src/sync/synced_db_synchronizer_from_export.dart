import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';

import 'synced_db_down_synchronizer.dart';

/// Compat
@Deprecated('Use SyncedDbSynchronizerFromExport instead')
typedef SyncedDbSynchronizerExport = SyncedDbSynchronizerFromExport;

/// Sync from export
class SyncedDbSynchronizerFromExport
    with SyncedDbDownSynchronizerMixin
    implements SyncedDbDownSynchronizer {
  SyncedDbSynchronizerFromExport(
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
      var sourceDb = await importDatabaseAny(
        data,
        newDatabaseFactoryMemory(),
        'export',
      );
      await databaseMerge(await db.database, sourceDatabase: sourceDb);
      await sourceDb.close();
    }
  }
}
