---
name: tekaly-sembast-synced-rpc-synced-source
description: >-
  Use when exposing a tekaly synced source over a web socket rpc server
  (SyncedSourceRpcServer) or synchronizing a local database with a remote
  source through SyncedSourceRpcClient, with tekaly_sembast_synced_rpc.
---

# Synced source over rpc (tekaly_sembast_synced_rpc)

A `SyncedSourceRpcServer` serves any `SyncedSource` (sembast, firestore,
memory...) over a web socket (`tekartik_rpc`); a `SyncedSourceRpcClient` is
itself a `SyncedSource`, so a `SyncedDbSynchronizer` (sembast) or a
`SyncedSdbSynchronizer` (sdb) can synchronize a local database with it.

## Guidelines

* Server side: import `package:tekaly_sembast_synced_rpc/rpc_server.dart`
  (also exports `tekartik_web_socket`), call
  `SyncedSourceRpcServer.serve(delegate:, webSocketChannelServerFactory:,
  port:)` and share `server.uri`. Close it with `await server.close()`.
* Client side: import `rpc_client.dart`, create
  `SyncedSourceRpcClient(uri:, webSocketChannelClientFactory:)`; it auto
  connects and reconnects. Its `onMetaInfo()` is real time (long polling on
  the server), so `autoSync: true` synchronizers react immediately.
* Pick the channel factories per platform: `webSocketChannelFactoryMemory`
  (from `tekartik_rpc`/`tekartik_web_socket`) in tests, the io factories
  (`tekartik_web_socket_io`) on the server, the browser ones
  (`tekartik_web_socket_browser`) in a web app.
* The delegate does the real work: `SyncedSourceSembast(database:)`
  (`synced_db_sembast.dart`) persists the change log in a sembast database,
  `SyncedSourceFirestore` proxies firestore, `SyncedSourceMemory` is for
  tests.
* Records travel json encoded; nothing to register, the client and server
  init their cv builders.
* Test a client with the shared suites (`runSyncedSourceTest`) from
  `tekaly_synced_db_common_test` / `tekaly_sembast_synced_test`.

## Examples

```dart
import 'package:tekaly_sembast_synced/synced_db_sembast.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:tekartik_rpc/rpc_client.dart';
import 'package:tekartik_rpc/rpc_server.dart';

Future<void> main() async {
  // In memory web sockets (tests); use the io/browser factories otherwise.
  var factory = webSocketChannelFactoryMemory;

  // Server: serve a sembast backed source
  var delegate = await newInMemorySyncedSourceSembast();
  var server = await SyncedSourceRpcServer.serve(
    delegate: delegate,
    webSocketChannelServerFactory: factory.server,
  );

  // Client: a SyncedSource for any synchronizer
  var source = SyncedSourceRpcClient(
    uri: server.uri,
    webSocketChannelClientFactory: factory.client,
  );
  var syncedDb = SyncedDb.newInMemory();
  var synchronizer = SyncedDbSynchronizer(db: syncedDb, source: source, autoSync: true);
  await syncedDb.initialSynchronizationDone();

  await synchronizer.close();
  await syncedDb.close();
  await source.close();
  await server.close();
}
```
