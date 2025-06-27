import 'dart:io';

import 'package:path/path.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

import 'import_common.dart';

/// Io export extension
extension SyncedDbExportIoExt on SyncedDb {
  Future<void> exportDatabase({
    /// Deprecated use dir
    String? assetsFolder,

    /// Destination folder (create export.jsonl and export_meta.json)
    String? dir,
  }) async {
    dir ??= assetsFolder!;
    await Directory(dir).create(recursive: true);
    var file = File(join(dir, syncedDbExportFilename));
    var fileMeta = File(join(dir, syncedDbExportMetaFilename));

    var sdb = await database;
    var lines = await exportDatabaseLines(
      sdb,
      storeNames: getNonEmptyStoreNames(sdb).toList()
        ..removeWhere(
          (element) => [dbSyncRecordStoreRef.name].contains(element),
        ),
    );
    //print(jsonPretty(map));
    // ignore: invalid_use_of_visible_for_testing_member
    var syncMeta = (await getSyncMetaInfo());
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncMeta: $syncMeta');
    }
    if (syncMeta != null) {
      await file.writeAsString(
        '${exportLinesToJsonStringList(lines).join('\n')}\n',
      );
      var exportMeta = SyncedDbExportMeta()
        ..sourceVersion.setValue(syncMeta.sourceVersion.v)
        ..lastTimestamp.setValue(syncMeta.lastTimestamp.v?.toIso8601String())
        ..lastChangeId.setValue(syncMeta.lastChangeId.v);
      //print(jsonPretty(exportMeta.toModel()));
      await fileMeta.writeAsString(jsonEncode(exportMeta.toMap()));
    }
  }
}
