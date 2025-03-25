import 'package:tkcms_common/tkcms_sembast.dart';

/// Model to a json map
CvMapModel modelToJsonMap(CvModel model) {
  return CvMapModel()..fromMap(
    sembastCodecDefault.jsonEncodableCodec.encode(model.toMap()) as Map,
  );
}

/// Model helpers
extension CvMapModelSembastSyncedRpcExt on CvModel {
  /// Convert to a json map
  CvMapModel toJsonMap() => modelToJsonMap(this);
}

/// Map helpers
extension MapSembastSyncedRpcExt on Map {
  /// Convert to a sembast model
  T jsonToModel<T extends CvModel>() => jsonMapToModel(this);
}

/// json map to a model
T jsonMapToModel<T extends CvModel>(Map map) {
  var decodeMap = sembastCodecDefault.jsonEncodableCodec.decode(map) as Map;
  return decodeMap.cv<T>();
}
