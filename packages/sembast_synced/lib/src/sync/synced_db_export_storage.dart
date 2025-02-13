import 'package:cv/cv_json.dart';
import 'package:path/path.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_export.dart';

import 'import_common.dart';

/// Export file name
String getExportFileName(int changeId) => 'export_$changeId.jsonl';

/// Export meta file name
String getExportMetaFileName({String? suffix}) =>
    'export_meta${suffix ?? ''}.json';

/// Export result (only if metaOnly is false)
class SyncedDbExportResult {
  final int? exportSize;

  SyncedDbExportResult({required this.exportSize});
}

/// Expor helper
extension SyncedDbExportStorageExt on SyncedDb {
  /// Export
  /// * `export_meta<suffix>.json`
  /// * `export_<changeId>.jsonl`
  Future<SyncedDbExportResult> exportDatabaseToStorage({
    required SyncedDbStorageExportContext exportContext,
    bool? metaOnly,
    bool? noMeta,
  }) async {
    metaOnly ??= false;
    noMeta ??= false;
    var exportInfo = await exportInMemory();
    int? exportSize;

    var exportMeta = exportInfo.metaInfo.toJson();

    var storage = exportContext.storage;
    var bucket = exportContext.bucketName;
    var rootPath = exportContext.rootPath;
    var changeId = exportInfo.metaInfo.lastChangeId.v!;
    var suffix = exportContext.metaBasenameSuffix;

    if (!metaOnly) {
      var exportContent = exportLinesToJsonlString(exportInfo.data);
      exportSize = exportContent.length;

      /// Write content
      await storage
          .bucket(bucket)
          .file(url.join(rootPath, getExportFileName(changeId)))
          .writeAsString(exportContent);
    }

    if (!noMeta) {
      /// Write meta
      await storage
          .bucket(bucket)
          .file(url.join(rootPath, getExportMetaFileName(suffix: suffix)))
          .writeAsString(exportMeta);
    }
    return SyncedDbExportResult(exportSize: exportSize);
  }
}
