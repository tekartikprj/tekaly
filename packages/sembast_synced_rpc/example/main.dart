// ignore_for_file: avoid_print

// A synced source served over a web socket and used through the rpc client,
// in one process on in memory web sockets.
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';

Future<void> main() async {
  // In memory web sockets (tests, this example); see the README for io and
  // the browser.
  var factory = webSocketChannelFactoryMemory;

  // Server: serves any SyncedSource, here an in memory one.
  var server = await SyncedSourceRpcServer.serve(
    delegate: SyncedSourceMemory(),
    webSocketChannelServerFactory: factory.server,
  );

  // Client: a SyncedSource itself, reached through the server.
  var source = SyncedSourceRpcClient(
    uri: server.uri,
    webSocketChannelClientFactory: factory.client,
  );

  var record = await source.putSourceRecord(
    CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = 'note'
        ..key.v = 'n1'
        ..value.v = {'title': 'Hello'}),
  );
  print('change id: ${record.syncChangeId.v}');

  var list = await source.getSourceRecordList();
  print('keys: ${list.list.map((record) => record.record.v!.key.v).toList()}');
  print('last change id: ${(await source.getMetaInfo())?.lastChangeId.v}');

  // close() also ends the onMetaInfo() streams of the client.
  await source.close();
  await server.close();
}
