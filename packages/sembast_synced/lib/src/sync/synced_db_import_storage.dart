import 'package:cv/cv_json.dart';
import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/sembast_synced.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';

import 'import_common.dart';

/// Export file name
String getExportFileName(int changeId) => 'export_$changeId.jsonl';

/// Export meta file name
String getExportMetaFileName({String? suffix}) =>
    'export_meta${suffix ?? ''}.json';

/// Expor helper
extension SyncedDbImportStorageExt on SyncedDb {
  /// Export
  /// * `export_meta<suffix>.json`
  /// * `export_<changeId>.jsonl`
  Future<void> importDatabaseFromStorage(
      {required SyncedDbStorageImportContext importContext}) async {
    await fetchAndImport(fetchExport: (int changeId) async {
      if (importContext is SyncedDbStorageExportContext) {
        var storage = importContext.storage;
        var bucket = importContext.bucketName;
        var rootPath = importContext.rootPath;
        return await storage
            .bucket(bucket)
            .file(url.join(rootPath, getExportFileName(changeId)))
            .readAsString();
      } else {
        throw UnimplementedError();
      }
    }, fetchExportMeta: () async {
      if (importContext is SyncedDbStorageExportContext) {
        var storage = importContext.storage;
        var bucket = importContext.bucketName;
        var rootPath = importContext.rootPath;
        var suffix = importContext.metaBasenameSuffix;
        return asModel(jsonDecode(await storage
            .bucket(bucket)
            .file(url.join(rootPath, getExportMetaFileName(suffix: suffix)))
            .readAsString()) as Map);
      } else {
        throw UnimplementedError();
      }
    });
  }
}
