/// A synced source server
library;

import 'package:tekaly_sembast_synced_rpc/src/rpc_message.dart';
import 'package:tekartik_rpc/rpc_server.dart';

class _SyncedSourceRpcService extends RpcServiceBase {
  late _SyncedSourceRpcServer rpcServer;
  _SyncedSourceRpcService() : super(syncedSourceRpcServiceName);
}

/// A synced source server
abstract class SyncedSourceRpcServer {
  /// Server uri
  Uri get uri;

  /// Serve a new server
  static Future<SyncedSourceRpcServer> serve({
    WebSocketChannelServerFactory? webSocketChannelServerFactory,
    int? port,
  }) async {
    var service = _SyncedSourceRpcService();
    var rpcServer = await RpcServer.serve(
      webSocketChannelServerFactory: webSocketChannelServerFactory,
      services: [service],
      port: port,
    );
    var syncedSourceRpcServer = _SyncedSourceRpcServer(rpcServer: rpcServer);
    service.rpcServer = syncedSourceRpcServer;
    return syncedSourceRpcServer;
  }

  /// Close the server
  Future<void> close();
}

class _SyncedSourceRpcServer implements SyncedSourceRpcServer {
  final RpcServer rpcServer;

  _SyncedSourceRpcServer({required this.rpcServer});

  @override
  Uri get uri => rpcServer.uri;

  @override
  Future<void> close() async {
    await rpcServer.close();
  }
}
