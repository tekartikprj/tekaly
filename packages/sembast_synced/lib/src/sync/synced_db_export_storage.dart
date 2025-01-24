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

/// Expor helper
extension SyncedDbExportStorageExt on SyncedDb {
  /// Export
  /// * export_meta<suffix>.json
  /// * export_<changeId>.jsonl
  Future<void> exportDatabaseToStorage(
      {required SyncedDbStorageExportContext exportContext}) async {
    var exportInfo = await exportInMemory();

    var exportContent = exportLinesToJsonlString(exportInfo.data);
    var exportMeta = exportInfo.metaInfo.toJson();

    var storage = exportContext.storage;
    var bucket = exportContext.bucketName;
    var rootPath = exportContext.rootPath;
    var changeId = exportInfo.metaInfo.lastChangeId.v!;
    var suffix = exportContext.metaBasenameSuffix;

    /// Write content
    await storage
        .bucket(bucket)
        .file(url.join(rootPath, getExportFileName(changeId)))
        .writeAsString(exportContent);

    /// Write meta
    await storage
        .bucket()
        .file(url.join(rootPath, getExportMetaFileName(suffix: suffix)))
        .writeAsString(exportMeta);
  }
}
