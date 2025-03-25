/// A synced source server
library;

import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/src/rpc_message.dart';
import 'package:tekaly_sembast_synced_rpc/src/rpc_utils.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_rpc/rpc_server.dart';
import 'package:tkcms_common/tkcms_api.dart';
import 'package:tkcms_common/tkcms_server.dart';

extension on RpcMethodCall {
  T cv<T extends CvModel>() => (arguments as Map).cv<T>();
}

class _SyncedSourceRpcService extends RpcServiceBase {
  late _SyncedSourceRpcServer rpcServer;

  _SyncedSourceRpcService() : super(syncedSourceRpcServiceName);

  Future<Object?> wrapResult(Future<ApiResult> Function() action) async {
    return (await wrapActionToApiResponse(action)).toMap();
  }

  @override
  Future<Object?> onCall(RpcServerChannel channel, RpcMethodCall methodCall) {
    return wrapResult(() async {
      switch (methodCall.method) {
        case requestPutSourceRecordCommand:
          var query = methodCall.cv<PutSourceRecordApiQuery>();
          var record = query.record.v!.jsonToModel<CvSyncedSourceRecord>();
          record = await rpcServer.delegate.putSourceRecord(record);
          return (PutSourceRecordApiResult()..record.v = record.toJsonMap());
        case requestGetSourceRecordCommand:
          var query = methodCall.cv<GetSourceRecordApiQuery>();
          var sourceRecordRef = SyncedDataSourceRef(
            syncId: query.syncId.v,
            store: query.store.v,
            key: query.key.v,
          );
          var record = await rpcServer.delegate.getSourceRecord(
            sourceRecordRef,
          );
          return (GetSourceRecordApiResult()
            ..record.setValue(record?.toJsonMap()));
        case requestGetSourceRecordListCommand:
          var query = methodCall.cv<GetSourceRecordListApiQuery>();

          var recordList = await rpcServer.delegate.getSourceRecordList(
            afterChangeId: query.afterChangeId.v,
            limit: query.limit.v,
            includeDeleted: query.includeDeleted.v,
          );
          return GetSourceRecordListApiResult()
            ..records.v =
                recordList.list.map((item) => item.toJsonMap()).toList()
            ..lastChangeId.setValue(recordList.lastChangeId);
        case requestGetMetaInfoCommand:
          var metaInfoRecord = await rpcServer.delegate.getMetaInfo();
          return GetMetaInfoApiResult()..metaInfo.setValue(metaInfoRecord);
        case requestPutMetaInfoCommand:
          var query = methodCall.cv<PutMetaInfoApiQuery>();
          // ignore: invalid_use_of_visible_for_testing_member
          var metaInfoRecord = await rpcServer.delegate.putMetaInfo(
            query.metaInfo.v!,
          );
          return PutMetaInfoApiResult()..metaInfo.setValue(metaInfoRecord);
        case requestGetMetaInfoChangedCommand:
          var query = methodCall.cv<GetMetaInfoApiChangedQuery>();
          var currentMetaInfo = query.metaInfo.v;
          var completer = Completer<CvMetaInfo?>();
          var subscription = rpcServer.delegate.onMetaInfo().listen((event) {
            // print('server: onMetaInfo $event');
            if (event == null) {
              if (currentMetaInfo != null) {
                if (!completer.isCompleted) {
                  completer.complete(null);
                }
              }
            } else {
              var metaInfo = CvMetaInfo()..copyFrom(event);
              if (metaInfo != currentMetaInfo) {
                if (!completer.isCompleted) {
                  completer.complete(metaInfo);
                }
              }
            }
          });
          try {
            var metaInfo = await completer.future.timeout(
              const Duration(minutes: 1),
            );

            return GetMetaInfoApiChangedResult()..metaInfo.setValue(metaInfo);
          } finally {
            subscription.cancel().unawait();
          }
      }

      throw (ApiError()
            ..code.v = apiErrorCodeUnimplemented
            ..message.v = 'Missing entry point for $methodCall'
            ..noRetry.v = true)
          .exception();
    });
  }
}

/// A synced source server
abstract class SyncedSourceRpcServer {
  /// Server uri
  Uri get uri;

  /// Serve a new server
  static Future<SyncedSourceRpcServer> serve({
    required SyncedSource delegate,
    WebSocketChannelServerFactory? webSocketChannelServerFactory,
    int? port,
  }) async {
    var service = _SyncedSourceRpcService();
    var rpcServer = await RpcServer.serve(
      webSocketChannelServerFactory: webSocketChannelServerFactory,
      services: [service],
      port: port,
    );
    var syncedSourceRpcServer = _SyncedSourceRpcServer(
      rpcServer: rpcServer,
      delegate: delegate,
    );
    service.rpcServer = syncedSourceRpcServer;
    return syncedSourceRpcServer;
  }

  /// Close the server
  Future<void> close();
}

class _SyncedSourceRpcServer implements SyncedSourceRpcServer {
  final SyncedSource delegate;
  final RpcServer rpcServer;

  _SyncedSourceRpcServer({required this.rpcServer, required this.delegate}) {
    initSembastSyncedRpcBuilders();
  }

  @override
  Uri get uri => rpcServer.uri;

  @override
  Future<void> close() async {
    await rpcServer.close();
  }
}
