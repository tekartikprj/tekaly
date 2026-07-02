import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb_codec.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb_export.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

/// Decode export data (either a jsonl string or an already decoded list of
/// lines) into a list of raw export lines.
Object _decodeTekalyExportAny(Object srcData) {
  if (srcData is List) {
    return srcData;
  }
  if (srcData is String) {
    var trimmed = srcData.trim();
    try {
      var decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded;
      }
    } catch (_) {}
    var lines = const LineSplitter().convert(trimmed);
    if (lines.isNotEmpty) {
      return lines.map((line) => jsonDecode(line)).toList();
    }
  }
  throw FormatException('invalid export format (${srcData.runtimeType})');
}

class _ParsedTekalyExport {
  _ParsedTekalyExport(this.syncMeta, this.stores);

  final Map<String, Object?>? syncMeta;
  final Map<String, Map<String, Object?>> stores;
}

_ParsedTekalyExport _parseTekalyExportLines(List lines) {
  if (lines.isEmpty) {
    throw const FormatException('invalid export format (empty)');
  }
  var header = lines.first;
  if (header is! Map || header['tekaly_export'] != 1) {
    throw const FormatException('invalid export format');
  }
  var rest = lines.skip(1).toList();

  Map<String, Object?>? syncMeta;
  if (rest.isNotEmpty) {
    var first = rest.first;
    if (first is Map && first[storeExportKey] == null) {
      syncMeta = Map<String, Object?>.from(first);
      rest = rest.skip(1).toList();
    }
  }

  var stores = <String, Map<String, Object?>>{};
  String? currentStore;
  for (var line in rest) {
    if (line is Map) {
      var storeName = line[storeExportKey]?.toString();
      currentStore = storeName;
      if (storeName != null) {
        stores.putIfAbsent(storeName, () => <String, Object?>{});
      }
    } else if (line is List && currentStore != null) {
      if (line.length >= 2) {
        var key = line[0];
        var value = line[1];
        if (key != null) {
          stores[currentStore]![key as String] = sdbValueFromJsonEncodable(
            value,
          );
        }
      }
    }
  }
  return _ParsedTekalyExport(syncMeta, stores);
}

/// Sync either from a tekaly export.
abstract class SyncedSdbDownSynchronizer {
  /// Target db.
  SyncedSdb get db;

  /// Synchronize (down).
  Future<void> sync();
}

/// Sync from a tekaly export.
class SyncedSdbSynchronizerFromTekalyExport
    implements SyncedSdbDownSynchronizer {
  /// Sync from a tekaly export.
  SyncedSdbSynchronizerFromTekalyExport(
    this.db, {
    required this.fetchExport,
    required this.fetchExportMeta,
  });

  @override
  final SyncedSdb db;

  /// Only sync if fetch export does not return null.
  final SyncedDbSynchronizerFetchExport fetchExport;

  /// Only sync if fetch export does not return null.
  final SyncedDbSynchronizerFetchExportMeta fetchExportMeta;

  @override
  Future<void> sync() async {
    var meta = await db.getSyncMetaInfo();
    var newMeta = SyncedDbExportMeta()..fromMap(await fetchExportMeta());
    var newLastChangeId = newMeta.lastChangeId.v!;
    if ((meta?.sourceVersion.v != newMeta.sourceVersion.v) ||
        (newLastChangeId > (meta?.lastChangeId.v ?? 0))) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('importing data $newMeta');
      }

      var data = await fetchExport(newLastChangeId);
      var lines = _decodeTekalyExportAny(data);
      if (lines is! List) {
        throw const FormatException(
          'invalid export format (expect json lines format .jsonl)',
        );
      }
      var parsed = _parseTekalyExportLines(lines);
      var rawDb = await db.database;
      var storeNames = [...parsed.stores.keys, sdbSyncMetaStoreRef.name];

      await rawDb.inTransaction(
        storeNames: storeNames,
        mode: SdbTransactionMode.readWrite,
        run: (txn) async {
          for (var entry in parsed.stores.entries) {
            var store = SdbStoreRef<String, SdbModel>(entry.key);
            var existing = await store.findRecords(txn);
            var existingMap = <String, SdbModel>{
              for (var record in existing) record.ref.key: record.value,
            };
            for (var kv in entry.value.entries) {
              var original = existingMap.remove(kv.key);
              if (!const DeepCollectionEquality().equals(original, kv.value)) {
                await store.record(kv.key).put(txn, kv.value as SdbModel);
              }
            }
            for (var remainingKey in existingMap.keys) {
              await store.record(remainingKey).delete(txn);
            }
          }

          var metaRecord = sdbSyncMetaStoreRef.record('info').cv()
            ..lastChangeId.v = newMeta.lastChangeId.v
            ..lastTimestamp.v = SdbTimestamp.tryParse(newMeta.lastTimestamp.v)
            ..sourceVersion.v = newMeta.sourceVersion.v;
          await metaRecord.put(txn);
        },
      );
    }
  }
}

/// Import helper.
extension SyncedSdbImportExt on SyncedSdb {
  /// Fetch and import (tekaly format).
  Future<void> fetchAndImport({
    /// Only sync if fetch export does not return null.
    required SyncedDbSynchronizerFetchExport fetchExport,

    /// Only sync if fetch export does not return null.
    required SyncedDbSynchronizerFetchExportMeta fetchExportMeta,
  }) async {
    var synchronizer = SyncedSdbSynchronizerFromTekalyExport(
      this,
      fetchExport: fetchExport,
      fetchExportMeta: fetchExportMeta,
    );
    await synchronizer.sync();
  }

  /// Imports a database snapshot exported with [SyncedSdbExportExt.exportInMemory].
  Future<void> importFromMemory({
    /// Export info to import.
    required SyncedDbExportInfo exportInfo,
  }) async {
    await fetchAndImport(
      fetchExport: (int changeId) async {
        return exportInfo.data.map((line) => jsonEncode(line)).join('\n');
      },
      fetchExportMeta: () async {
        return exportInfo.metaInfo.toMap();
      },
    );
  }
}
