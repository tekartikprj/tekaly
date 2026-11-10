# tekaly_sembast_synced_rpc

Serve a tekaly *synced source* over a web socket and use it from another
process. `SyncedSourceRpcServer` wraps any `SyncedSource` (Firestore, sembast,
memory...); `SyncedSourceRpcClient` is a `SyncedSource` itself, so any
synchronizer can sync a local database with it: `SyncedSdbSynchronizer`
(`tekaly_sdb_synced`, for new code) or the legacy sembast
`SyncedDbSynchronizer`.

Built on `tekartik_rpc` (json over a web socket). Not on pub.dev: depend on
it by git.

## Getting started

```yaml
dependencies:
  tekaly_sembast_synced_rpc:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/sembast_synced_rpc
```

Dart SDK `^3.12.0`. A server and its client in one process, on in memory web
sockets ([example/main.dart](example/main.dart), `dart run example/main.dart`):

```dart
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';

Future<void> main() async {
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
  print('change id: ${record.syncChangeId.v}'); // change id: 1

  await source.close();
  await server.close();
}
```

## Platforms

| Side | Where | Channel factory |
|---|---|---|
| Server | Dart VM (io) | the io one by default (`tekartik_web_socket_io`), `port:` to choose the port |
| Client | VM, web, Flutter | the universal one by default (io or browser web socket) |
| Tests | anywhere | `webSocketChannelFactoryMemory` (`.server` and `.client`) |

`rpc_client.dart` and `rpc_server.dart` also export `tekartik_web_socket`
(the factories).

## Sync a local database with it

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
    autoSync: true, // follows the server meta info (real time)
  );
  await syncedSdb.initialSynchronizationDone();
  // ... read and write noteStore on await syncedSdb.database

  await synchronizer.close(); // does not close the source
  await source.close();
  await syncedSdb.close();
}
```

## What to know

- **No authorization.** Every connected client reads every record and can
  call the test only commands: `putRawRecord` (any change id) and
  `putMetaInfo` (a higher `minIncrementalChangeId` forces every client into a
  full sync). On io the server listens on every interface. Serve it on a
  trusted network only (localhost, tests, a private network).
- `onMetaInfo()` is real time through a long poll: the server answers when
  the meta info of its source changes, or after one minute (the client asks
  again). A failing source stream answers the poll with its error and the
  client asks again a second later; only an error of the first read is
  added to the stream.
- `close()` the client: it ends its `onMetaInfo()` streams, later calls
  throw a `StateError`. Closing the server does not end the polls in
  progress: their source subscription lives until it times out (one minute
  at most).
- Records and meta info travel json encoded with the sembast codec
  (timestamps and blobs are kept).
- The name says sembast, the server and the client do not care: they work
  with any source and any synchronizer. Local sembast databases are legacy,
  start new code on sdb (`tekaly_sdb_synced`).
- Test a client with the shared suites: `runSyncedSourceTest` of
  `tekaly_synced_db_common_test`, the synchronizer suites of
  `tekaly_sdb_synced_test` / `tekaly_sembast_synced_test`.

More in the
[tekaly-sembast-synced-rpc-synced-source](skills/tekaly-sembast-synced-rpc-synced-source/SKILL.md)
skill.
