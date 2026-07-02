import 'dart:io';

import 'package:path/path.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

import '../export/sembast_import_export.dart';
import 'import_common.dart';

/// Io export extension for [SyncedDbExportInfo].
extension SyncedDbExportInfoIoExt on SyncedDbExportInfo {
  /// Writes this export info to files in [dir] (creates
  /// [syncedDbExportFilename] and [syncedDbExportMetaFilename]).
  Future<void> writeToDir(String dir) async {
    await Directory(dir).create(recursive: true);
    var file = File(join(dir, syncedDbExportFilename));
    var fileMeta = File(join(dir, syncedDbExportMetaFilename));

    await file.writeAsString(getJsonlExport());
    await fileMeta.writeAsString(getMetaExport());
  }
}

/// Io export extension
extension SyncedDbExportIoExt on SyncedDb {
  /// Exports the database to files in [dir].
  ///
  /// When [dir] is omitted, [assetsFolder] is used for backwards compatibility.
  // @Deprecated('use tekaly or legacy')
  Future<void> exportDatabase({
    /// Deprecated use dir
    String? assetsFolder,

    /// Destination folder (create export.jsonl and export_meta.json)
    String? dir,
  }) {
    return exportDatabaseTekaly(dir: dir);
  }

  /// Exports the database to files in [dir].
  ///
  /// When [dir] is omitted, [assetsFolder] is used for backwards compatibility.
  Future<void> tekalyExportDatabase({
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
    var lines = await sembastToTekalyExportDatabaseLines(
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

  /// Exports the database to files in [dir].
  ///
  /// When [dir] is omitted, [assetsFolder] is used for backwards compatibility.
  Future<void> exportDatabaseTekaly({
    /// Deprecated use dir
    String? assetsFolder,

    /// Destination folder (create export.jsonl and export_meta.json)
    String? dir,
  }) async {
    var result = await exportInMemory();
    dir ??= assetsFolder!;
    await result.writeToDir(dir);
  }

  /// Legacy export
  @visibleForTesting
  Future<List> exportLinesLegacy() async {
    var sdb = await database;
    var lines = await exportDatabaseLines(
      sdb,
      storeNames: getNonEmptyStoreNames(sdb).toList()
        ..removeWhere(
          (element) => [dbSyncRecordStoreRef.name].contains(element),
        ),
    );
    return lines;
  }

  /// Exports the database to files in [dir].
  ///
  /// When [dir] is omitted, [assetsFolder] is used for backwards compatibility.
  Future<void> exportDatabaseLegacy({
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
