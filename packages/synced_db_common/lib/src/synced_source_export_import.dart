import 'package:cv/cv.dart';

import 'model/source_record.dart';
import 'synced_db_common_types.dart';
import 'synced_db_export_info.dart';
import 'synced_source.dart';
import 'synced_source_codec.dart';
import 'synced_source_export.dart';

/// Export helper for any [SyncedSourceRead] (memory, firestore, api...),
/// using the same tekaly export format as the synced databases (see
/// `SyncedDbExportExt.exportInMemory`/`SyncedDbImportExt.importFromMemory`).
extension SyncedSourceExportExt on SyncedSourceRead {
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
    SyncedDbTimestamp? lastTimestamp;
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
          syncedDbValueToJsonEncodable(record.record.v!.value.v),
        ]);
      }
    }

    return SyncedDbExportInfo(metaInfo: exportMeta, data: lines);
  }
}

/// Import helper for any [SyncedSourceWrite] (memory, firestore, api...).
extension SyncedSourceImportExt on SyncedSourceWrite {
  /// Imports a database snapshot (tekaly format, as produced by
  /// [SyncedSourceExportExt.exportInMemory]) into this source, pushing each
  /// record as a new change.
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
                ..value.v = syncedDbValueFromJsonEncodable(rawValue) as Model?),
          );
        }
      }
    }
  }
}
