import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' as fs;

/// True for the values sdb stores as is.
bool isSdbSupportedTypeOrNull(Object? value) {
  if (value == null) {
    return true;
  }
  return value is num ||
      value is String ||
      value is bool ||
      value is SdbBlob ||
      value is SdbTimestamp;
}

Object? _toSdb(Object? value) {
  if (isSdbSupportedTypeOrNull(value)) {
    return value;
  }
  if (value is fs.Timestamp) {
    return SdbTimestamp(value.seconds, value.nanoseconds);
  }
  if (value is fs.Blob) {
    return SdbBlob(value.bytes);
  }
  if (value is Map) {
    Map<String, Object?>? clone;
    value.forEach((key, item) {
      var converted = _toSdb(item);
      if (!identical(converted, item)) {
        clone ??= Map<String, Object?>.from(value);
        clone![key as String] = converted;
      }
    });
    return clone ?? asModel(value);
  }
  if (value is List) {
    List<Object?>? clone;
    for (var i = 0; i < value.length; i++) {
      var item = value[i];
      var converted = _toSdb(item);
      if (!identical(converted, item)) {
        clone ??= List<Object?>.from(value);
        clone[i] = converted;
      }
    }
    return clone ?? value;
  }
  throw ArgumentError.value(value, 'value', 'not supported in sdb');
}

/// Convert a firestore document map to a value sdb can store.
///
/// Timestamps and blobs are converted, anything sdb cannot hold (a document
/// reference, a geo point, ...) throws an [ArgumentError], which sends the
/// change to the dead letter queue instead of breaking the synchronization.
SdbModel firestoreMapToSdb(Model map) => asModel(_toSdb(map) as Map);
