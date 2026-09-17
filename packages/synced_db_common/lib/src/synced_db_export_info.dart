import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:sembast/utils/sembast_import_export.dart'
    show exportLinesToJsonlString;

import 'synced_source_export.dart';

/// Export info (tekaly export format), meta and data lines.
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
