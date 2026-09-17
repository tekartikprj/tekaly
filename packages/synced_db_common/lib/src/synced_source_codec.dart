// ignore: implementation_imports
import 'package:sembast/src/api/protected/codec.dart';

/// Json encodable codec of the tekaly export format: values are encoded as
/// `{"$timestamp": "<iso8601>"}` and `{"$blob": "<base64>"}`.
final _codec = sembastCodecJsonEncodableCodec(sembastCodecDefaultV2);

/// Convert a synced db value (num, String, bool, Map, List,
/// `SyncedDbTimestamp`, `SyncedDbBlob`) to a json encodable value using the
/// tekaly export format.
///
/// Each provider (sembast, sdb, synced source) must produce and parse the
/// same content.
Object? syncedDbValueToJsonEncodable(Object? value) {
  if (value == null) {
    return null;
  }
  return _codec.encode(value);
}

/// Convert a json encodable value (tekaly export format) back to a synced db
/// value.
Object? syncedDbValueFromJsonEncodable(Object? value) {
  if (value == null) {
    return null;
  }
  return _codec.decode(value);
}
