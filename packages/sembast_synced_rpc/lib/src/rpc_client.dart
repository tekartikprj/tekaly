import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/src/rpc_message.dart';
import 'package:tekaly_sembast_synced_rpc/src/rpc_utils.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_rpc/rpc_client.dart';
import 'package:tkcms_common/tkcms_api.dart';

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
    initSembastSyncedRpcBuilders();
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
          request.data.v,
        )).cv<ApiResponse>();
    if (response.error.isNotNull) {
      throw ApiException(error: response.error.v);
    } else {
      var result = response.result.v!;
      return result.cv<T>();
    }
  }

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(
    CvSyncedSourceRecord record,
  ) async {
    var result = await _sendRequest<PutSourceRecordApiResult>(
      (PutSourceRecordApiQuery()..record.v = modelToJsonMap(record)).request(
        requestPutSourceRecordCommand,
      ),
    );
    return result.record.v!.jsonToModel();
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(
    SyncedDataSourceRef sourceRef,
  ) async {
    var result = await _sendRequest<GetSourceRecordApiResult>(
      (GetSourceRecordApiQuery()
            ..syncId.setValue(sourceRef.syncId)
            ..store.setValue(sourceRef.store)
            ..key.setValue(sourceRef.key))
          .request(requestGetSourceRecordCommand),
    );
    return result.record.v?.jsonToModel<CvSyncedSourceRecord>();
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) async {
    var result = await _sendRequest<GetSourceRecordListApiResult>(
      (GetSourceRecordListApiQuery()
            ..afterChangeId.setValue(afterChangeId)
            ..limit.setValue(limit)
            ..includeDeleted.setValue(includeDeleted))
          .request(requestGetSourceRecordListCommand),
    );
    return SyncedSourceRecordList(
      result.records.v!
          .map((item) => item.jsonToModel<CvSyncedSourceRecord>())
          .toList(),
      result.lastChangeId.v,
    );
  }

  @override
  Future<CvMetaInfo?> getMetaInfo() async {
    var result = await _sendRequest<GetMetaInfoApiResult>(
      ApiEmpty().request(requestGetMetaInfoCommand),
    );
    return result.metaInfo.v;
  }

  @override
  Future<CvMetaInfo> putMetaInfo(CvMetaInfo info) async {
    var result = await _sendRequest<PutMetaInfoApiResult>(
      (PutMetaInfoApiQuery()..metaInfo.v = info).request(
        requestPutMetaInfoCommand,
      ),
    );
    return result.metaInfo.v!;
  }

  Future<CvMetaInfo> _getMetaInfoChanged(CvMetaInfo? info) async {
    var result = await _sendRequest<GetMetaInfoApiChangedResult>(
      (GetMetaInfoApiChangedQuery()..metaInfo.v = info).request(
        requestGetMetaInfoChangedCommand,
      ),
    );
    return result.metaInfo.v!;
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) {
    late StreamController<CvMetaInfo?> controller;
    controller = StreamController<CvMetaInfo?>(
      onListen: () async {
        var metaInfo = await getMetaInfo();
        if (!controller.isClosed) {
          controller.add(metaInfo);
        }
        while (!controller.isClosed) {
          try {
            var newMetaInfo = await _getMetaInfoChanged(metaInfo);
            if (!controller.isClosed) {
              if (newMetaInfo != metaInfo) {
                metaInfo = newMetaInfo;
                controller.add(metaInfo);
              }
            } else {
              return;
            }
          } catch (_) {
            // print('Error $e');
          }
        }
      },
      onCancel: () {
        controller.close();
      },
    );
    return controller.stream;
  }
}
