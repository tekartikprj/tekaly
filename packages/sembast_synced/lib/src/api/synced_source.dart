// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:cv/cv.dart';

// ignore: implementation_imports
import 'package:sembast/src/api/protected/codec.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';

//var _codec = sembastCodecJsonEncodableCodec(null);
var _codec = sembastCodecJsonEncodableCodec(sembastCodecDefaultV2);
Object? jsonEncodeSembastValueOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _codec.encode(value);
}

Object? jsonDecodeSembastValueOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _codec.decode(value);
}

/// Export/import helper for any [SyncedSource] (e.g. [SyncedSourceApi]),
/// using the same tekaly export format as [SyncedDb]/[SyncedSdb] (see
/// `SyncedDbExportExt.exportInMemory`/`SyncedDbImportExt.importFromMemory`).
extension SyncedSourceExportExt on SyncedSource {
  /// Export to memory (tekaly format).
  ///
  /// Since a [SyncedSource] is a change log (not a snapshot store), this
  /// fetches every change in memory, keeps only the latest value per
  /// store/key and sorts the result by store then key so the output is
  /// deterministic.
  Future<SyncedDbExportInfo> exportInMemory() async {
    var meta = await getMetaInfo();
    var list = await getAllSourceRecordList(includeDeleted: true);

    // Keep only the latest record per store/key (last one wins) and track
    // the most recent timestamp seen.
    var latestByKey = <SyncedRecordKey, CvSyncedSourceRecord>{};
    Timestamp? lastTimestamp;
    for (var record in list.list) {
      latestByKey[record.syncedKey] = record;
      var timestamp = record.syncTimestamp.v;
      if (timestamp != null &&
          (lastTimestamp == null || timestamp.compareTo(lastTimestamp) > 0)) {
        lastTimestamp = timestamp;
      }
    }
    var lastChangeId = list.lastChangeId ?? meta?.lastChangeId.v ?? 0;

    var exportMeta = SyncedDbExportMeta()
      ..sourceVersion.setValue(meta?.version.v)
      ..lastTimestamp.setValue(lastTimestamp?.toIso8601String())
      ..lastChangeId.setValue(lastChangeId);

    var lines = <Object>[
      {'tekaly_export': 1, 'version': 1},
      exportMeta.toMap(),
    ];

    var recordsByStore = <String, List<CvSyncedSourceRecord>>{};
    for (var record in latestByKey.values) {
      if (record.isDeleted) {
        continue;
      }
      (recordsByStore[record.recordStore] ??= []).add(record);
    }
    var storeNames = recordsByStore.keys.toList()..sort();
    for (var storeName in storeNames) {
      var records = recordsByStore[storeName]!
        ..sort((r1, r2) => r1.recordKey.compareTo(r2.recordKey));
      lines.add({'store': storeName});
      for (var record in records) {
        lines.add([
          record.recordKey,
          jsonEncodeSembastValueOrNull(record.record.v!.value.v),
        ]);
      }
    }

    return SyncedDbExportInfo(metaInfo: exportMeta, data: lines);
  }

  /// Imports a database snapshot (tekaly format, as produced by
  /// [exportInMemory]) into this source, pushing each record as a new
  /// change.
  Future<void> importFromMemory({
    /// Export info to import.
    required SyncedDbExportInfo exportInfo,
  }) async {
    var lines = exportInfo.data;
    if (lines.isEmpty) {
      throw const FormatException('invalid export format (empty)');
    }
    var header = lines.first;
    if (header is! Map || header['tekaly_export'] != 1) {
      throw const FormatException('invalid export format');
    }

    String? currentStore;
    for (var line in lines.skip(1)) {
      if (line is Map) {
        currentStore = line['store'] as String?;
      } else if (line is List && currentStore != null) {
        if (line.length >= 2) {
          var key = line[0] as String;
          var rawValue = line[1];
          await putSourceRecord(
            CvSyncedSourceRecord()
              ..record.v = (CvSyncedSourceRecordData()
                ..store.v = currentStore
                ..key.v = key
                ..value.v = jsonDecodeSembastValueOrNull(rawValue) as Model?),
          );
        }
      }
    }
  }
}
