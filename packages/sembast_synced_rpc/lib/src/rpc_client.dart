import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/src/rpc_message.dart';
import 'package:tekartik_rpc/rpc_client.dart';
import 'package:tkcms_common/tkcms_api.dart';
import 'package:tkcms_common/tkcms_sembast.dart';

/// A synced source client
abstract class SyncedSourceRpcClient implements SyncedSource {
  /// Construct a synced source client
  factory SyncedSourceRpcClient({
    WebSocketChannelClientFactory? webSocketChannelClientFactory,
    required Uri uri,
  }) => _SyncedSourceRpcClient(
    uri: uri,
    webSocketChannelClientFactory: webSocketChannelClientFactory,
  );
}

class _SyncedSourceRpcClient
    with SyncedSourceDefaultMixin
    implements SyncedSourceRpcClient {
  final Uri uri;
  final WebSocketChannelClientFactory? webSocketChannelClientFactory;
  late final RpcClient rpcClient;
  _SyncedSourceRpcClient({
    required this.uri,
    required this.webSocketChannelClientFactory,
  }) {
    rpcClient = AutoConnectRpcClient.autoConnect(
      uri,
      onConnect: (client) {},
      webSocketChannelClientFactory: webSocketChannelClientFactory,
    );
  }

  Future<T> _sendRequest<T extends ApiResult>(ApiRequest request) async {
    var response =
        (await rpcClient.sendServiceRequest<Map>(
          syncedSourceRpcServiceName,
          request.apiCommand,
          request.toMap(),
        )).cv<ApiResponse>();
    if (response.error.isNotNull) {
      throw ApiException(error: response.error.v);
    } else {
      var result = response.result.v!;
      return result.cv<T>();
    }
  }

  CvMapModel _modelToJsonMap(CvModel model) {
    return CvMapModel()..fromMap(
      sembastCodecDefault.jsonEncodableCodec.encode(model.toMap()) as Map,
    );
  }

  T _jsonMapToModel<T extends CvModel>(Map map) {
    var decodeMap = sembastCodecDefault.jsonEncodableCodec.decode(map) as Map;
    return decodeMap.cv<T>();
  }

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(
    CvSyncedSourceRecord record,
  ) async {
    var result = await _sendRequest<PutSourceRecordApiResult>(
      (PutSourceRecordApiQuery()..record.v = _modelToJsonMap(record)).request(
        requestPutSourceRecordCommand,
      ),
    );
    return _jsonMapToModel(result.record.v!);
  }
}
