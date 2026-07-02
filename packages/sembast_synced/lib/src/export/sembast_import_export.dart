library;

import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source.dart';
import 'package:tekaly_sembast_synced/src/sembast/sembast_import.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/env_utils.dart';

void _log(Object? message) {
  // ignore: avoid_print
  print(message);
}

const String _dbVersion = 'version';
const String _exportSignatureKey = 'tekaly_export';
const String _stores = 'stores';
const String _name = 'name'; // for store
const String _keys = 'keys'; // list
const String _values = 'values'; // list
const String _store = 'store'; // store name in export lines
const int _exportSignatureVersion = 1;

///
/// Return the data in an exported format where each item in the list can be JSONified.
/// If simply encoded as list of json string, it makes it suitable to archive
/// a mutable export on a git file system.
///
/// An optional [storeNames] can specify the list of stores to export. If null
/// All stores are exported.
///
/// The format is agnostic so each provider must be able to generate the same content
/// And parse the same content too (sembast, sdb, synced source)
Future<List<Object>> sembastToTekalyExportDatabaseLines(
  Database db, {
  List<Object>? meta,
  List<String>? storeNames,
}) async {
  var lines = <Object>[];

  await _exportDatabase(
    db,
    storeNames: storeNames,
    exportMeta: (Model map) {
      lines.add(map);
      if (meta != null) {
        lines.addAll(meta);
      }
    },
    exportStore: (Model map) {
      lines.add(newModel()..[_store] = map[_name]);
      var keys = map[_keys] as List;
      var values = map[_values] as List;
      for (var i = 0; i < keys.length; i++) {
        lines.add([keys[i], values[i]]);
      }
    },
  );

  return lines;
}

///
/// Return the data in an exported format that (can be JSONified).
///
/// An optional [storeNames] can specify the list of stores to export. If null
/// All stores are exported.
///
Future<void> _exportDatabase(
  Database db, {
  List<String>? storeNames,

  required void Function(Map<String, Object?>) exportMeta,
  required void Function(Map<String, Object?>) exportStore,
}) {
  var jsonEncodableCodec = sembastCodecDefaultV2.jsonEncodableCodec;
  return db.transaction((txn) async {
    var metaExport = <String, Object?>{
      // our export signature
      _exportSignatureKey: _exportSignatureVersion,
      // the db version
      _dbVersion: db.version,
    };
    exportMeta(metaExport);

    // export all records from each store

    // Make it safe to iterate in an async way
    var sembastDatabase = db as SembastDatabase;
    var allStoreNames = List<String>.of(sembastDatabase.storeNames);
    // Filter stores
    if (storeNames != null) {
      allStoreNames.removeWhere((store) => !storeNames.contains(store));
    }
    allStoreNames.sort();

    for (var storeName in allStoreNames) {
      var store = StoreRef<Object, Object>(storeName);
      final keys = <Object?>[];
      final values = <Object?>[];

      final storeExport = <String, Object?>{
        _name: storeName,
        _keys: keys,
        _values: values,
      };

      var currentRecords = await store.find(txn);
      for (var record in currentRecords) {
        keys.add(record.key);
        values.add(jsonEncodableCodec.encode(record.value));
        if (sembastDatabase.cooperator?.needCooperate ?? false) {
          await sembastDatabase.cooperator!.cooperate();
        }
      }

      // Only add store if it has content
      if (keys.isNotEmpty) {
        exportStore(storeExport);
      }
    }
  });
}

///
/// Import the exported data (using exportDatabaseLines) into a new database
///
/// An optional [storeNames] can specify the list of stores to import. If null
/// All stores are exported.
///
Future<Database> tekalyToSembastImportDatabaseLines(
  Iterable srcData,
  DatabaseFactory dstFactory,
  String dstPath, {

  List<String>? storeNames,
}) async {
  cvAddConstructors([SyncedDbExportMeta.new]);
  if (srcData.isEmpty) {
    throw const FormatException('invalid export format (empty)');
  }
  Object? metaMap = srcData.first;
  if (metaMap is Map) {
    _checkMeta(metaMap);
  } else {
    throw const FormatException('invalid export format header');
  }

  srcData = srcData.skip(1);

  // 2nd line is meta
  var rawSyncMeta = srcData.firstOrNull;
  if (debugSyncedSync) {
    _log('rawSyncMeta $rawSyncMeta');
  }
  // Not s store header
  var hasSyncInfoMeta = rawSyncMeta is Map && rawSyncMeta['store'] == null;
  if (hasSyncInfoMeta) {
    srcData = srcData.skip(1);
  }

  var mapSrcData = newModel();
  metaMap.forEach((key, value) {
    mapSrcData[key as String] = value;
  });

  String? currentStore;
  var keys = <Object?>[];
  var values = <Object?>[];
  var stores = <Object?>[];
  void closeCurrentStore() {
    if (currentStore != null) {
      if (keys.isNotEmpty) {
        final storeExport = <String, Object?>{
          _name: currentStore,
          _keys: List<Object>.from(keys),
          _values: List<Object>.from(values),
        };
        stores.add(storeExport);
        keys.clear();
        values.clear();
        currentStore = null;
      }
    }
  }

  for (var line in srcData) {
    if (line is Map) {
      closeCurrentStore();
      var storeName = line[_store]?.toString();
      if (storeName != null) {
        currentStore = storeName;
      }
    } else if (currentStore == null) {
      // skipping
    } else if (line is List && currentStore != null) {
      if (line.length >= 2) {
        var key = line[0];
        var value = line[1];
        if (key != null && value != null) {
          keys.add(key);
          values.add(value);
        }
      }
    } else {
      // skipping
    }
  }
  closeCurrentStore();
  mapSrcData[_stores] = stores;
  var db = await _importDatabase(
    mapSrcData,
    dstFactory,
    dstPath,

    storeNames: storeNames,
  );
  if (hasSyncInfoMeta) {
    final dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>(
      'local_sync_meta',
    );
    late var dbSyncMetaInfoRef = dbSyncMetaStoreRef.record('info');
    var meta = rawSyncMeta.cv<SyncedDbExportMeta>();
    var timestamp = SyncedDbTimestamp.tryParse(meta.lastTimestamp.v);
    var dbSyncMetaInfo = dbSyncMetaInfoRef.cv()
      ..lastChangeId.setValue(meta.lastChangeId.v)
      ..lastTimestamp.setValue(timestamp)
      ..sourceVersion.setValue(meta.sourceVersion.v);
    await dbSyncMetaInfo.put(db);
  }
  return db;
}

void _checkMeta(Map meta) {
  // check signature
  if (meta[_exportSignatureKey] != _exportSignatureVersion) {
    throw const FormatException('invalid export format');
  }
}

/// Import the exported data (using exportDatabase) into a new database
///
/// An optional [storeNames] can specify the list of stores to import. If null
/// All stores are exported.
///
/// If a codec was used, you must specify the same codec for import.
Future<Database> _importDatabase(
  Map srcData,
  DatabaseFactory dstFactory,
  String dstPath, {

  List<String>? storeNames,
}) async {
  await dstFactory.deleteDatabase(dstPath);

  // check signature
  _checkMeta(srcData);

  final version = srcData[_dbVersion] as int?;

  final db = await dstFactory.openDatabase(
    dstPath,
    version: version,
    mode: DatabaseMode.empty,
  );
  await db.transaction((txn) async {
    final storesExport = (srcData[_stores] as Iterable?)
        ?.toList(growable: false)
        .cast<Map>();
    if (storesExport != null) {
      for (var storeExport in storesExport) {
        final storeName = storeExport[_name] as String;

        // Filter store
        if (storeNames != null) {
          if (!storeNames.contains(storeName)) {
            continue;
          }
        }

        final keys = (storeExport[_keys] as Iterable).toList(growable: false);
        final values = List<Object>.from(storeExport[_values] as Iterable);

        var store = StoreRef(storeName);
        for (var i = 0; i < keys.length; i++) {
          var key = keys[i] as Object;
          await store
              .record(key)
              .put(txn, jsonDecodeSembastValueOrNull(values[i]));
        }
      }
    }
  });
  return db;
}

///
/// Import the exported data (using exportDatabase or exportDatabaseLines or their json encoding or a string of it) into a new database
///
/// An optional [storeNames] can specify the list of stores to import. If null
/// All stores are exported.
///
Future<Database> tekalyToSembastImportDatabaseAny(
  Object srcData,
  DatabaseFactory dstFactory,
  String dstPath, {

  List<String>? storeNames,
}) {
  Future<Database> linesImport(List lines) {
    return tekalyToSembastImportDatabaseLines(
      lines,
      dstFactory,
      dstPath,
      storeNames: storeNames,
    );
  }

  srcData = decodeImportAny(srcData);
  try {
    if (srcData is Map) {
      throw const FormatException(
        'invalid export format (expect json lines format .jsonl)',
      );
    } else if (srcData is List) {
      return linesImport(srcData);
    }
  } catch (e) {
    if (isDebug) {
      // ignore: avoid_print
      print('import error $e');
    }
    throw FormatException('invalid export format (error: $e)');
  }
  throw FormatException('invalid export format (${srcData.runtimeType})');
}
