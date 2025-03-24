// ignore_for_file: avoid_print

import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:tekaly_sembast_synced_test/synced_source_test.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

Future<void> main() async {
  var factory = webSocketChannelFactoryMemory;
  var rpcServer = await SyncedSourceRpcServer.serve(
    webSocketChannelServerFactory: factory.server,
  );
  var rpcClient = SyncedSourceRpcClient(
    uri: rpcServer.uri,
    webSocketChannelClientFactory: factory.client,
  );
  return;

  // ignore: dead_code
  runSyncedSourceTest(() async {
    return rpcClient;
  });
}
