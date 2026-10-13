import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced/synced_db_sembast.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:test/test.dart';

void main() {
  test('putRawRecord through rpc keeps the change id', () async {
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
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      await rpcClient.putRawRecord(
        CvSyncedSourceRecord()
          ..syncChangeId.v = 5
          ..syncTimestamp.v = SyncedDbTimestamp(1, 0)
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'entity'
            ..key.v = 'a1'
            ..value.v = {'name': 'raw'}),
      );
      var list = await delegate.getSourceRecordList(includeDeleted: true);
      // Raw: the given change id, no meta update (a put would give 1).
      expect(list.list.single.syncChangeId.v, 5);
      expect(await delegate.getMetaInfo(), isNull);
    } finally {
      await rpcServer.close();
    }
  });
}
