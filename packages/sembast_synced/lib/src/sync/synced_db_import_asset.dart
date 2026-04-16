import 'package:cv/cv.dart';
import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/src/api/import_common.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_export.dart';
import 'package:tekartik_app_common_utils/asset/asset_bundle.dart';

import '../../synced_db.dart';

/// Import from asset
class SyncedDbAssetImportContext {
  /// Asset bundle
  final TkAssetBundle assetBundle;

  /// Asset root path
  final String rootPath;

  /// Creates the asset import context.
  SyncedDbAssetImportContext({
    required this.assetBundle,
    required this.rootPath,
  });
}

/// Imports a synced database snapshot from assets.
extension SyncedDbImportAssetExt on SyncedDb {
  /// Imports a database snapshot from the configured asset bundle.
  Future<void> importDatabaseFromAsset({
    required SyncedDbAssetImportContext importContext,
  }) async {
    var assetBundle = importContext.assetBundle;
    var rootPath = importContext.rootPath;
    await fetchAndImport(
      fetchExport: (int changeId) async {
        try {
          var data = await assetBundle.loadString(
            url.join(rootPath, syncedDbExportFilename),
          );
          return data;
        } catch (e, st) {
          if (isDebug) {
            // ignore: avoid_print
            print('No data in assets $e $st');
          }
          rethrow;
        }
      },
      fetchExportMeta: () async {
        try {
          var map =
              jsonDecode(
                    await assetBundle.loadString(
                      url.join(rootPath, syncedDbExportMetaFilename),
                    ),
                  )
                  as Map;
          return asModel(map);
        } catch (e, st) {
          if (isDebug) {
            // ignore: avoid_print
            print('No meta data in assets $e $st');
          }
          rethrow;
        }
      },
    );
  }
}
