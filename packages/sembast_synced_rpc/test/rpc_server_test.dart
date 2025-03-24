import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:test/test.dart';

void main() {
  rpcTests(webSocketChannelFactoryMemory);
}

/// Rpc tests
void rpcTests(WebSocketChannelFactory factory) {
  group('rpc', () {
    late SyncedSourceRpcServer rpcServer;
    late SyncedSourceRpcClient rpcClient;
    setUp(() async {
      rpcServer = await SyncedSourceRpcServer.serve(
        webSocketChannelServerFactory: factory.server,
      );
      rpcClient = SyncedSourceRpcClient(uri: rpcServer.uri);
    });

    tearDown(() async {
      await rpcServer.close();
      await rpcClient.close();
    });
  });
}
