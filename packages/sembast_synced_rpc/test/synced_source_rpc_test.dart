// ignore_for_file: avoid_print, unused_import

import 'package:tekaly_sembast_synced/synced_db_sembast.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:tekaly_sembast_synced_test/synced_source_test.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_rpc/rpc_client.dart';
import 'package:tekartik_rpc/rpc_server.dart';

Future<void> main() async {
  // debugRpcServer = devWarning(true);
  // debugRpcClient = devWarning(true);
  var factory = webSocketChannelFactoryMemory;
  var delegate = await newInMemorySyncedSourceSembast();
  var rpcServer = await SyncedSourceRpcServer.serve(
    delegate: delegate,
    webSocketChannelServerFactory: factory.server,
  );
  var rpcClient = SyncedSourceRpcClient(
    uri: rpcServer.uri,
    webSocketChannelClientFactory: factory.client,
  );
  //return;

  // ignore: dead_code
  runSyncedSourceTest(() async {
    return rpcClient;
  });
}
