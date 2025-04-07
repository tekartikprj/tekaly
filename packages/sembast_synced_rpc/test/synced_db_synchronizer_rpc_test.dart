import 'package:tekaly_sembast_synced/synced_db_sembast.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:tekaly_sembast_synced_test/synced_db_synchronizer_test.dart';
// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

void main() async {
  group('synced_db_synchronizer_test', () {
    Future<SyncTestsContext> setupContext() async {
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
      //    setUp(() async {
      return SyncTestsContext()
        ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
        ..source = rpcClient;
    }

    //  });
    syncTests(setupContext);
  });
}
