import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

const String _timestampKey = r'$timestamp';
const String _blobKey = r'$blob';
const String _escapeKey = r'$';

bool _isBasicTypeOrNull(Object? value) =>
    value == null || value is num || value is String || value is bool;

bool _looksLikeEncodedValue(Map map) {
  if (map.length == 1) {
    var key = map.keys.first;
    return key is String && key.startsWith(r'$');
  }
  return false;
}

/// Convert a synced sdb value to a json encodable value using the tekaly
/// export format (values encoded as `{"$timestamp": ...}` / `{"$blob": ...}`).
///
/// This must stay in sync with the format produced by
/// `sembastToTekalyExportDatabaseLines` in `tekaly_sembast_synced` since both
/// providers must produce/parse the same tekaly export content.
Object? sdbValueToJsonEncodable(Object? value) {
  if (_isBasicTypeOrNull(value)) {
    return value;
  }
  if (value is SdbTimestamp) {
    return <String, Object?>{_timestampKey: value.toIso8601String()};
  }
  if (value is SdbBlob) {
    return <String, Object?>{_blobKey: value.toBase64()};
  }
  if (value is Map) {
    if (_looksLikeEncodedValue(value)) {
      return <String, Object?>{_escapeKey: value};
    }
    return value.map(
      (key, item) => MapEntry(key as String, sdbValueToJsonEncodable(item)),
    );
  }
  if (value is List) {
    return value.map(sdbValueToJsonEncodable).toList();
  }
  throw ArgumentError.value(value);
}

/// Convert a json encodable value (tekaly export format) back to a synced
/// sdb value.
Object? sdbValueFromJsonEncodable(Object? value) {
  if (_isBasicTypeOrNull(value)) {
    return value;
  }
  if (value is Map) {
    if (_looksLikeEncodedValue(value)) {
      var key = value.keys.first as String;
      var encoded = value.values.first;
      if (key == _timestampKey) {
        return SdbTimestamp.parse(encoded as String);
      }
      if (key == _blobKey) {
        return SdbBlob.fromBase64(encoded as String);
      }
      if (key == _escapeKey) {
        return sdbValueFromJsonEncodable(encoded);
      }
    }
    return value.map(
      (key, item) => MapEntry(key as String, sdbValueFromJsonEncodable(item)),
    );
  }
  if (value is List) {
    return value.map(sdbValueFromJsonEncodable).toList();
  }
  throw ArgumentError.value(value);
}
