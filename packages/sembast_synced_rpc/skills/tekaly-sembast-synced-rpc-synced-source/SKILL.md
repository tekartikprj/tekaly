---
name: tekaly-sembast-synced-rpc-synced-source
description: >-
  Use when exposing a tekaly synced source over a web socket rpc server
  (SyncedSourceRpcServer) or synchronizing a local database (sdb
  SyncedSdbSynchronizer, or the legacy sembast SyncedDbSynchronizer) with a
  remote source through SyncedSourceRpcClient, with
  tekaly_sembast_synced_rpc: channel factories per platform, real time meta
  info (long poll), closing, security limits.
---

# Synced source over rpc (tekaly_sembast_synced_rpc)

A `SyncedSourceRpcServer` serves any `SyncedSource` (sembast, firestore,
memory...) over a web socket (`tekartik_rpc`); a `SyncedSourceRpcClient` is
itself a `SyncedSource`, so a `SyncedSdbSynchronizer` (sdb, for new code) or
the legacy `SyncedDbSynchronizer` (sembast) can synchronize a local database
with it. The package name says sembast; neither side depends on a sembast
local database.

## Guidelines

* Not on pub.dev, git dependency:

  ```yaml
  dependencies:
    tekaly_sembast_synced_rpc:
      git:
        url: https://github.com/tekartikprj/tekaly
        path: packages/sembast_synced_rpc
  ```

* Server side: import `package:tekaly_sembast_synced_rpc/rpc_server.dart`
  (also exports `tekartik_web_socket`), call
  `SyncedSourceRpcServer.serve(delegate:, webSocketChannelServerFactory:,
  port:)` and share `server.uri`. Close it with `await server.close()`.
* Client side: import `rpc_client.dart`, create
  `SyncedSourceRpcClient(uri:, webSocketChannelClientFactory:)`; it auto
  connects and reconnects until `close()` (which also ends its `onMetaInfo()`
  streams; later calls throw a `StateError`).
* `onMetaInfo()` is real time (long polling: the server answers when the
  meta info of its source changes, or after one minute), so `autoSync: true`
  synchronizers react at once. A failed first read is added to the stream as
  an error and retried; a failing source stream during a poll answers the
  poll with its error, the client asks again a second later.
* Channel factories: `webSocketChannelFactoryMemory` (`.server` and
  `.client`) in tests; the server defaults to the io factory (Dart VM only),
  the client to the universal one (io or browser web socket).
* The delegate does the real work: `SyncedSourceSembast(database:)` /
  `newInMemorySyncedSourceSembast()` (`synced_db_sembast.dart`) persists the
  change log in a sembast database, `SyncedSourceFirestore` proxies firestore,
  `SyncedSourceMemory` (`synced_db_internals.dart`) is for tests.
* Records and meta info travel json encoded (sembast codec: timestamps and
  blobs kept); nothing to register, the client and server init their cv
  builders.
* Security: there is no authorization. Every connected client reads every
  record and can call the test only `putRawRecord` / `putMetaInfo` (a
  higher `minIncrementalChangeId` forces every client into a full sync); on
  io the server listens on every interface. Serve it on a trusted network
  only (localhost, tests), never as a public endpoint.
* Closing the server does not end the polls in progress: their source
  subscription lives until it times out (one minute at most). Close the
  clients first in tests.
* Test a client with the shared suites: `runSyncedSourceTest` from
  `tekaly_synced_db_common_test`, `allSyncedDbTests` from
  `tekaly_sdb_synced_test`, `syncTests` from `tekaly_sembast_synced_test`.

## Examples

### Server and client in one process (tests)

```dart
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';

Future<void> main() async {
  var factory = webSocketChannelFactoryMemory;
  var server = await SyncedSourceRpcServer.serve(
    delegate: SyncedSourceMemory(),
    webSocketChannelServerFactory: factory.server,
  );
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
  print(record.syncChangeId.v); // 1

  await source.close();
  await server.close();
}
```

### A local sdb database synchronized through the rpc client

```dart
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';

final noteStore = SdbStoreRef<String, SdbModel>('note');

Future<void> syncNotes(Uri serverUri) async {
  var syncedSdb = SyncedSdb.openDatabase(
    name: 'notes.db',
    databaseFactory: newSdbFactoryMemory(), // the app factory in an app
    options: SyncedSdbOptions(
      openDatabaseOptions: SdbOpenDatabaseOptions(
        version: 1,
        schema: SdbDatabaseSchema(
          stores: [noteStore.schema(), ...syncedSdbMetaSchema.stores],
        ),
      ),
    ),
  );
  var source = SyncedSourceRpcClient(uri: serverUri);
  var synchronizer = SyncedSdbSynchronizer(
    db: syncedSdb,
    source: source,
    autoSync: true,
  );
  await syncedSdb.initialSynchronizationDone();

  await synchronizer.close(); // does not close the source
  await source.close();
  await syncedSdb.close();
}
```
