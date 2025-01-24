import 'dart:convert';
import 'dart:io';
import 'package:cv/cv.dart';
import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_export.dart';

import '../../synced_db.dart';

extension SyncedDbImportIoExt on SyncedDb {
  Future<void> importDatabaseFromFiles(
      {
      /// Destination folder (import export.jsonl and export_meta.json)
      required String dir}) async {
    await fetchAndImport(fetchExport: (int changeId) async {
      var file = File(join(dir, syncedDbExportFilename));
      return file.readAsString();
    }, fetchExportMeta: () async {
      var fileMeta = File(join(dir, syncedDbExportMetaFilename));
      var map = jsonDecode(await fileMeta.readAsString()) as Map;
      return asModel(map);
    });
  }
}
