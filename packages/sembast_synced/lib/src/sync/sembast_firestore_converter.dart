import 'package:cv/cv.dart';
import 'package:sembast/timestamp.dart' as sembast;
import 'package:tekartik_firebase_firestore/firestore.dart' as firestore;

import 'model/source_meta_info.dart';
import 'model/source_record.dart';

/// True for null, num, String, bool
bool isBasicTypeOrNull(dynamic value) {
  if (value == null) {
    return true;
  } else if (value is num || value is String || value is bool) {
    return true;
  }
  return false;
}

dynamic _toFirestore(dynamic value) {
  if (isBasicTypeOrNull(value)) {
    return value;
  }

  if (value is sembast.Timestamp) {
    return firestore.Timestamp(value.seconds, value.nanoseconds);
  }

  if (value is Map) {
    var map = value;
    Map? clone;
    map.forEach((key, item) {
      var converted = _toFirestore(item);
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
      var converted = _toFirestore(item);
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
dynamic sembastToFirestore(dynamic value) {
  dynamic converted;
  try {
    converted = _toFirestore(value);
  } on ArgumentError catch (e) {
    throw ArgumentError.value(
        e.invalidValue,
        '${(e.invalidValue as Object?)?.runtimeType} in $value',
        'not supported');
  }

  /// Ensure root is Map<String, Object?> if only Map
  if (converted is Map && (converted is! Map<String, Object?>)) {
    converted = converted.cast<String, Object?>();
  }
  return converted;
}

dynamic _toSembast(dynamic value) {
  if (isBasicTypeOrNull(value)) {
    return value;
  }

  if (value is firestore.Timestamp) {
    return sembast.Timestamp(value.seconds, value.nanoseconds);
  }

  if (value is Map) {
    var map = value;
    Map? clone;
    map.forEach((key, item) {
      var converted = _toSembast(item);
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
      var converted = _toSembast(item);
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
dynamic firestoreToSembast(dynamic value) {
  dynamic converted;
  try {
    converted = _toSembast(value);
  } on ArgumentError catch (e) {
    throw ArgumentError.value(
        e.invalidValue,
        '${(e.invalidValue as Object?)?.runtimeType} in $value',
        'not supported');
  }

  /// Ensure root is Map<String, Object?> if only Map
  if (converted is Map && (converted is! Map<String, Object?>)) {
    converted = converted.cast<String, Object?>();
  }
  return converted;
}

/// Map easy converter
Map<String, Object?> mapSembastToFirestore(Map<String, Object?> map) =>
    sembastToFirestore(map) as Map<String, Object?>;

extension MapSembastFromToFirestoreExt on Map<String, Object?> {
  Map<String, Object?> fromFirestore() => mapFirestoreToSembast(this);
  Map<String, Object?> toFirestore() => mapSembastToFirestore(this);
}

/// Map easy converter
Map<String, Object?> mapFirestoreToSembast(Map<String, Object?> map) =>
    firestoreToSembast(map) as Map<String, Object?>;

/// Snapshot to a cv record
T? cvRecordFromSnapshot<T extends CvModel>(
        firestore.DocumentSnapshot snapshot) =>
    (snapshot.exists)
        ? () {
            var data =
                firestoreToSembast(snapshot.data) as Map<String, Object?>;
            return cvBuildModel<T>(data)..fromMap(data);
          }()
        : null;

CvMetaInfoRecord? metaInfoRecordFromSnapshot(
        firestore.DocumentSnapshot snapshot) =>
    cvRecordFromSnapshot<CvMetaInfoRecord>(snapshot);

/// Copy the sync id
SyncedSourceRecord? sourceRecordFromSnapshot(
        firestore.DocumentSnapshot snapshot) =>
    cvRecordFromSnapshot<SyncedSourceRecord>(snapshot)
      ?..syncId.v = snapshot.ref.id;

/// Copy the sync id
List<SyncedSourceRecord?> sourceRecordFromSnapshots(
        List<firestore.DocumentSnapshot> snapshots) =>
    snapshots.map(sourceRecordFromSnapshot).toList();
