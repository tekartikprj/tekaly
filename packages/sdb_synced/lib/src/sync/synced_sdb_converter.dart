import 'dart:typed_data';

import 'package:cv/cv.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' as firestore;

/// True for null, num, String, bool
bool isBasicTypeOrNull(dynamic value) {
  if (value == null) {
    return true;
  } else if (value is num || value is String || value is bool) {
    return true;
  }
  return false;
}

dynamic _toSdb(dynamic value) {
  if (isBasicTypeOrNull(value)) {
    return value;
  }

  if (value is SyncedDbTimestamp) {
    return value.toDateTime(isUtc: true);
  }
  if (value is SyncedDbBlob) {
    return value.bytes;
  }

  if (value is Map) {
    var map = value;
    Map? clone;
    map.forEach((key, item) {
      var converted = _toSdb(item);
      if (!identical(converted, item)) {
        clone ??= Map<String, Object?>.from(map);
        clone![key] = converted;
      }
    });
    return clone ?? map;
  } else if (value is List) {
    var list = value;
    List? clone;
    for (var i = 0; i < list.length; i++) {
      var item = list[i];
      var converted = _toSdb(item);
      if (!identical(converted, item)) {
        clone ??= List.from(list);
        clone[i] = converted;
      }
    }
    return clone ?? list;
  } else {
    throw ArgumentError.value(value);
  }
}

/// Convert a sembast value to a json encodable value
dynamic syncedDbToSdb(dynamic value) {
  dynamic converted;
  try {
    converted = _toSdb(value);
  } on ArgumentError catch (e) {
    throw ArgumentError.value(
      e.invalidValue,
      '${(e.invalidValue as Object?)?.runtimeType} in $value',
      'not supported',
    );
  }

  /// Ensure root is Map<String, Object?> if only Map
  if (converted is Map && (converted is! Map<String, Object?>)) {
    converted = converted.cast<String, Object?>();
  }
  return converted;
}

dynamic _toSyncedDb(dynamic value) {
  // print('_toSyncedDb $value (${value.runtimeType})');
  if (isBasicTypeOrNull(value)) {
    return value;
  }

  /// Allow synced timestamp on input
  if (value is SyncedDbTimestamp) {
    return value;
  }
  if (value is DateTime) {
    return SyncedDbTimestamp.fromDateTime(value);
  }
  if (value is SyncedDbBlob) {
    return value;
  }
  if (value is Uint8List) {
    return SyncedDbBlob(value);
  }
  if (value is Map) {
    var map = value;
    Map? clone;
    map.forEach((key, item) {
      var converted = _toSyncedDb(item);
      if (!identical(converted, item)) {
        clone ??= Map<String, Object?>.from(map);
        clone![key] = converted;
      }
    });
    return clone ?? map;
  } else if (value is List) {
    var list = value;
    List? clone;
    for (var i = 0; i < list.length; i++) {
      var item = list[i];
      var converted = _toSyncedDb(item);
      if (!identical(converted, item)) {
        clone ??= List.from(list);
        clone[i] = converted;
      }
    }
    return clone ?? list;
  } else {
    throw ArgumentError.value(value);
  }
}

/// Convert a value from a firestore to sembast
dynamic sdbToSyncedDb(dynamic value) {
  dynamic converted;
  try {
    converted = _toSyncedDb(value);
  } on ArgumentError catch (e) {
    throw ArgumentError.value(
      e.invalidValue,
      '${(e.invalidValue as Object?)?.runtimeType} in $value',
      'not supported',
    );
  }

  /// Ensure root is Map<String, Object?> if only Map
  if (converted is Map) {
    return asModel(converted);
  }
  return converted;
}

/// Map easy converter
Map<String, Object?> mapSyncedDbToSdb(Map<String, Object?> map) =>
    syncedDbToSdb(map) as Map<String, Object?>;

extension MapSyncedDbFromToSdbExt on Map<String, Object?> {
  Map<String, Object?> fromSdb() => mapSdbToSyncedDb(this);
  Map<String, Object?> toSdb() => mapSyncedDbToSdb(this);
}

/// Map easy converter
Map<String, Object?> mapSdbToSyncedDb(Map<String, Object?> map) =>
    sdbToSyncedDb(map) as Map<String, Object?>;

/// Snapshot to a cv record
T? cvRecordFromSnapshot<T extends CvModel>(
  firestore.DocumentSnapshot snapshot,
) => (snapshot.exists)
    ? () {
        var data = sdbToSyncedDb(snapshot.data) as Map<String, Object?>;
        return cvBuildModel<T>(data)..fromMap(data);
      }()
    : null;
