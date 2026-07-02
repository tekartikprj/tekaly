import 'package:collection/collection.dart';
import 'package:path/path.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/export/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_common_utils/common_utils_import.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

/// Synced db export filename
var syncedDbExportFilename = 'export.jsonl';

/// Synced db export meta filename
var syncedDbExportMetaFilename = 'export_meta.json';

/// Assets root data parts
var assetsRootDataParts = ['assets', 'data'];

/// Default for flutter app
var assetsRootDataPath = url.joinAll(assetsRootDataParts);

/// Assets root data io path
var assetsRootDataIoPath = joinAll(assetsRootDataParts);

/// Export info
class SyncedDbExportInfo {
  /// Meta information
  final SyncedDbExportMeta metaInfo;

  /// data
  final List<Object> data;

  /// Export info
  SyncedDbExportInfo({required this.metaInfo, required this.data});

  @override
  int get hashCode => metaInfo.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SyncedDbExportInfo) return false;
    return metaInfo == other.metaInfo &&
        const DeepCollectionEquality().equals(metaInfo, other.metaInfo);
  }

  @override
  String toString() =>
      'SyncedDbExportInfo(metaInfo: $metaInfo, data: ${data.length})';
}

/// Export helper
extension SyncedDbExportInfoExt on SyncedDbExportInfo {
  /// Get json l export
  String getJsonlExport() {
    return exportLinesToJsonlString(data);
  }

  /// Get json meta export
  String getMetaExport() {
    return jsonEncode(metaInfo.toMap());
  }
}

/// Export helper
extension SyncedDbExportDbExt on SyncedDb {
  /// Export to memory removing meta
  Future<SyncedDbExportInfo> exportInMemoryLegacy() async {
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
    var syncMeta =
        (await getSyncMetaInfo()) ?? (DbSyncMetaInfo()..lastChangeId.v = 0);

    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncMeta: $syncMeta');
    }
    var exportMeta = SyncedDbExportMeta()
      ..sourceVersion.setValue(syncMeta.sourceVersion.v)
      ..lastTimestamp.setValue(syncMeta.lastTimestamp.v?.toIso8601String())
      ..lastChangeId.setValue(syncMeta.lastChangeId.v);
    return SyncedDbExportInfo(metaInfo: exportMeta, data: lines);
  }

  /// Export to memory removing meta
  Future<SyncedDbExportInfo> exportInMemory() async {
    var sdb = await database;
    //print(jsonPretty(map));
    // ignore: invalid_use_of_visible_for_testing_member
    var syncMeta =
        (await getSyncMetaInfo()) ?? (DbSyncMetaInfo()..lastChangeId.v = 0);

    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncMeta: $syncMeta');
    }
    var exportMeta = SyncedDbExportMeta()
      ..sourceVersion.setValue(syncMeta.sourceVersion.v)
      ..lastTimestamp.setValue(syncMeta.lastTimestamp.v?.toIso8601String())
      ..lastChangeId.setValue(syncMeta.lastChangeId.v);
    var stores = List.of(
      getNonEmptyStoreNames(sdb),
    ).where((store) => shouldSyncStore(store)).toList();
    var lines = await sembastToTekalyExportDatabaseLines(
      sdb,
      meta: [exportMeta.toMap()],
      storeNames: stores,
    );

    return SyncedDbExportInfo(metaInfo: exportMeta, data: lines);
  }
}
