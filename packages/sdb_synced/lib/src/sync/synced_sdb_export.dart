import 'dart:convert';

import 'package:tekaly_sdb_synced/src/sync/synced_sdb_codec.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

import 'synced_sdb_import.dart';

const String _dbVersionKey = 'version';
const String _exportSignatureKey = 'tekaly_export';

/// Store name key in export lines.
const String storeExportKey = 'store';
const int _exportSignatureVersion = 1;

/// Synced sdb export filename.
var syncedSdbExportFilename = 'export.jsonl';

/// Synced sdb export meta filename.
var syncedSdbExportMetaFilename = 'export_meta.json';

/// Names of the stores that should be part of a synced export (excludes
/// system and local only stores).
List<String> syncedSdbExportableStoreNames(SdbDatabase db) {
  var storeNames = Set.of(db.storeNames)
    ..removeAll([sdbSyncRecordStoreRef.name, sdbSyncMetaStoreRef.name])
    ..removeWhere((name) => name.startsWith(SyncedSdb.unsyncedStoreNamePrefix));
  return storeNames.toList()..sort();
}

///
/// Return the data in a tekaly exported format where each item in the list
/// can be JSONified.
///
/// An optional [storeNames] can specify the list of stores to export. If
/// null, all synced (non system, non local) stores are exported.
///
/// The format is agnostic so each provider must be able to generate the same
/// content and parse the same content too (sembast, sdb, synced source).
Future<List<Object>> sdbToTekalyExportDatabaseLines(
  SdbDatabase db, {
  List<Object>? meta,
  List<String>? storeNames,
}) async {
  var lines = <Object>[];
  lines.add(<String, Object?>{
    _exportSignatureKey: _exportSignatureVersion,
    _dbVersionKey: db.version,
  });
  if (meta != null) {
    lines.addAll(meta);
  }

  var allStoreNames = List<String>.of(
    storeNames ?? syncedSdbExportableStoreNames(db),
  )..sort();

  await db.inTransaction(
    storeNames: allStoreNames,
    mode: SdbTransactionMode.readOnly,
    run: (txn) async {
      for (var storeName in allStoreNames) {
        var store = SdbStoreRef<String, SdbModel>(storeName);
        var records = await store.findRecords(txn);
        if (records.isEmpty) {
          continue;
        }
        lines.add(<String, Object?>{storeExportKey: storeName});
        for (var record in records) {
          lines.add([record.ref.key, sdbValueToJsonEncodable(record.value)]);
        }
      }
    },
  );

  return lines;
}

Object? _jsonSorted(Object? value) {
  if (value is Map) {
    var sortedKeys = value.keys.cast<String>().toList()..sort();
    return {for (var key in sortedKeys) key: _jsonSorted(value[key])};
  }
  if (value is List) {
    return value.map(_jsonSorted).toList();
  }
  return value;
}

/// Convert export lines to a deterministic (sorted map keys) list of json
/// strings, suitable to archive a mutable export on a git file system.
List<String> sdbExportLinesToJsonStringList(List<Object> lines) =>
    lines.map((line) => jsonEncode(_jsonSorted(line))).toList();

/// Read to save string
String sdbExportLinesToJsonlString(List<Object> lines) =>
    sdbExportLinesToJsonStringList(lines).map((line) => '$line\n').join();

/// Export helper.
extension SyncedSdbExportExt on SyncedSdb {
  /// Export to memory (tekaly format).
  Future<SyncedDbExportInfo> exportInMemory() async {
    var db = await database;
    var syncMeta =
        (await getSyncMetaInfo()) ?? (SdbSyncMetaInfo()..lastChangeId.v = 0);

    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncMeta: $syncMeta');
    }
    var exportMeta = SyncedDbExportMeta()
      ..sourceVersion.setValue(syncMeta.sourceVersion.v)
      ..lastTimestamp.setValue(syncMeta.lastTimestamp.v?.toIso8601String())
      ..lastChangeId.setValue(syncMeta.lastChangeId.v);
    var lines = await sdbToTekalyExportDatabaseLines(
      db,
      meta: [exportMeta.toMap()],
      storeNames: syncedSdbExportableStoreNames(db),
    );

    return SyncedDbExportInfo(metaInfo: exportMeta, data: lines);
  }

  /// Export database to a JSON Lines string.
  Future<String> exportToJsonlString() async {
    var exportInfo = await exportInMemory();
    return sdbExportLinesToJsonlString(exportInfo.data);
  }

  /// Import database from a JSON Lines string.
  Future<void> importFromJsonlString(String jsonl) async {
    var lines = const LineSplitter()
        .convert(jsonl)
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line))
        .toList();

    if (lines.isEmpty) {
      throw const FormatException('empty jsonl');
    }

    var header = lines.first;
    if (header is! Map || header['tekaly_export'] != 1) {
      throw const FormatException('invalid export format');
    }

    var rest = lines.skip(1).toList();
    Map<String, Object?>? syncMeta;
    if (rest.isNotEmpty) {
      var first = rest.first;
      if (first is Map && first['store'] == null) {
        syncMeta = Map<String, Object?>.from(first);
      }
    }

    if (syncMeta == null) {
      throw const FormatException('missing sync meta info');
    }

    var exportMeta = SyncedDbExportMeta()..fromMap(syncMeta);
    var exportInfo = SyncedDbExportInfo(
      metaInfo: exportMeta,
      data: lines.cast<Object>(),
    );

    await importFromMemory(exportInfo: exportInfo);
  }
}
