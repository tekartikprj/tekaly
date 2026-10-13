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
    initBuilders();
    rpcClient = AutoConnectRpcClient.autoConnect(
      uri,
      onConnect: (client) {},
      webSocketChannelClientFactory: webSocketChannelClientFactory,
    );
  }

  /// True once closed: no request is sent anymore.
  var _closed = false;

  /// The active meta info streams, stopped on close.
  final _metaInfoPolls = <_MetaInfoPoll>{};

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (var poll in _metaInfoPolls.toList()) {
      poll.close();
    }
    await rpcClient.close();
  }

  Future<T> _sendRequest<T extends ApiResult>(ApiRequest request) async {
    if (_closed) {
      throw StateError('SyncedSourceRpcClient closed');
    }
    var response = (await rpcClient.sendServiceRequest<Map>(
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
  Future<void> putRawRecord(CvSyncedSourceRecord record) async {
    await _sendRequest<PutSourceRecordApiResult>(
      (PutSourceRecordApiQuery()..record.v = modelToJsonMap(record)).request(
        requestPutRawRecordCommand,
      ),
    );
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

  /// Wait for the server meta info to differ from [info], null when deleted.
  Future<CvMetaInfo?> _getMetaInfoChanged(CvMetaInfo? info) async {
    var result = await _sendRequest<GetMetaInfoApiChangedResult>(
      (GetMetaInfoApiChangedQuery()..metaInfo.v = info).request(
        requestGetMetaInfoChangedCommand,
      ),
    );
    return result.metaInfo.v;
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) =>
      _MetaInfoPoll(this).controller.stream;
}

/// Delay before trying again after a failed meta info read.
const _metaInfoRetryDelay = Duration(seconds: 1);

/// One meta info stream: the current meta info, then each change (long poll).
class _MetaInfoPoll {
  final _SyncedSourceRpcClient client;
  late final controller = StreamController<CvMetaInfo?>(
    onListen: _run,
    onCancel: close,
  );

  /// The pending wait before a retry, stopped on close.
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;

  _MetaInfoPoll(this.client);

  bool get _done => controller.isClosed || client._closed;

  Future<void> _run() async {
    if (_done) {
      close();
      return;
    }
    client._metaInfoPolls.add(this);
    try {
      CvMetaInfo? metaInfo;
      var first = true;
      while (!_done) {
        try {
          var newMetaInfo = first
              ? await client.getMetaInfo()
              : await client._getMetaInfoChanged(metaInfo);
          if (_done) {
            break;
          }
          if (first || newMetaInfo != metaInfo) {
            first = false;
            metaInfo = newMetaInfo;
            controller.add(metaInfo);
          }
        } catch (e, st) {
          if (_done) {
            break;
          }
          // An unreachable source reports an error until its meta info is
          // read once, the long poll (timing out when nothing changes) does
          // not.
          if (first) {
            controller.addError(e, st);
          }
          await _waitRetry();
        }
      }
    } finally {
      client._metaInfoPolls.remove(this);
    }
  }

  Future<void> _waitRetry() {
    var completer = _retryCompleter = Completer<void>();
    _retryTimer = Timer(_metaInfoRetryDelay, _stopWait);
    return completer.future;
  }

  void _stopWait() {
    _retryTimer?.cancel();
    _retryTimer = null;
    var completer = _retryCompleter;
    _retryCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void close() {
    _stopWait();
    controller.close();
  }
}
