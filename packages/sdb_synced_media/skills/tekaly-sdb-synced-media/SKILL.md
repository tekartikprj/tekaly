---
name: tekaly-sdb-synced-media
description: >-
  Use when storing media files (images, audio, any bytes) next to a synced
  sdb with tekaly_sdb_synced_media: SyncedMediaSdb (records in the synced
  `media` store, contents in an fs_shim file system), SyncedMediaSdbSynchronizer
  (upload, download, deletion propagation), the local cache modes (all, lru
  with maxCount/maxSize/prefetch, none), network urls (download, public,
  redirection) and the sources: Firebase Storage, api (client + server
  service), in memory, hybrid.
---

# Synced media (tekaly_sdb_synced_media)

Media records are regular synced records (store `media` of a `SyncedSdb`),
their contents are files in a local `fs_shim` file system and in a remote
`SyncedMediaSource` (`SyncedMediaSourceStorage` for Firebase Storage). A
local, unsynced status store (`local_media_status`) tracks for each media
whether its content is local, remote, deleted, plus its local path, size and
last access.

## Guidelines

* Import `package:tekaly_sdb_synced_media/synced_media.dart`;
  `synced_media_storage.dart` adds `SyncedMediaSourceStorage` and the url
  builders. Spread `syncedMediaSdbStoresDefault.schemaStores` (or your own
  `SyncedMediaSdbStores(mediaStoreName: ...)`) in the `SdbDatabaseSchema` of
  the synced sdb, next to `syncedSdbMetaSchema.stores`.
* `SyncedMediaSdb(fs:, database: await syncedSdb.database)` is local only:
  `addMediaFile(file: SyncedMediaFile.from(filename:), bytes:)` writes the
  content and the records (uploaded on the next sync), `deleteMediaFile(id)`
  marks it deleted (deleted from the source on the next sync),
  `readMediaFileBytes(id)` throws a `FileSystemException` when the content
  is not local.
* `SyncedMediaSdbSynchronizer(db:, source:, cacheOptions:, storeUrl:)`:
  `sync()` reconciles, uploads, deletes, downloads and trims the cache;
  `startAutoSync(dbSynchronizer.onSynced())` runs it after each database sync
  (that is when new/deleted records of other clients arrive); `lazySync()`
  coalesces calls and never throws; `close()` before closing the database.
* Read contents with `synchronizer.readMediaBytes(id)` (local, or from the
  source then kept per cache mode) or `getCachedMediaFile(id)` (local file or
  null); with an `lru` or `none` cache, never rely on
  `SyncedMediaSdb.readMediaFileBytes`.
* Cache modes: `SyncedMediaCacheOptions.all()` (default, download all on
  sync), `.lru(maxCount:, maxSize:, prefetch:)` (download on read, evict the
  least recently read above the limits, `prefetch` fills free room newest
  first on sync), `.none()` (nothing kept once uploaded). Local contents not
  uploaded yet are never evicted.
* Network urls: `synchronizer.getMediaUrl(id)` returns the url stored in the
  record (`storeUrl: true`) or asks the source (kept in memory), null before
  upload. `SyncedMediaSourceStorage` defaults to the storage download url
  (permanent token url on Flutter clients, null on the admin sdk);
  `urlBuilder: syncedMediaStoragePublicUrlBuilder()` computes the tokenless
  url (rules must allow public read); a custom `urlBuilder` gives a
  redirection url (your function answering 302).
* Pass `cacheControl: syncedMediaStorageCacheControlImmutable`: a media path
  never changes content.
* Sources (all `SyncedMediaSource`): `SyncedMediaSourceStorage` (direct),
  `SyncedMediaSourceApi(client:)` (through an api), `SyncedMediaSourceMemory`
  (in memory), `SyncedMediaSourceHybrid(readSource:, writeSource:)` (e.g.
  read directly, write through the api). The api is transport agnostic:
  implement `SyncedMediaApiClient.send(command, request)` (json maps) over
  your transport; on the server, `SyncedMediaApiService(source:,
  accessCheck:, maxSize:)` answers `handle(command, request)` when
  `handles(command)`. `SyncedMediaApiClientLocal(service:)` runs it in
  process. Contents travel base64 in json: keep them small or use urls.
* Media paths come from synced records: they are validated
  (`syncedMediaIsValidPath`, relative without `..`), invalid ones are
  rejected (fs, Storage, api) or skipped (synchronizer).
* Tests: `SyncedMediaSourceMemory`, or `SyncedMediaSourceStorage` on
  `newStorageServiceMemory()` (tekartik_firebase_storage_fs) with an app from
  `FirebaseLocal().initializeApp(options: FirebaseAppOptions(projectId:,
  storageBucket:))`.

## Examples

```dart
import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';

Future<void> main() async {
  var syncedSdb = SyncedSdb.newInMemory(
    options: SyncedSdbOptions(
      openDatabaseOptions: SdbOpenDatabaseOptions(
        version: 1,
        schema: SdbDatabaseSchema(
          stores: [
            ...syncedMediaSdbStoresDefault.schemaStores,
            ...syncedSdbMetaSchema.stores,
          ],
        ),
      ),
    ),
  );
  var dbSynchronizer = SyncedSdbSynchronizer(
    db: syncedSdb,
    source: SyncedSourceMemory(),
  );
  var mediaDb = SyncedMediaSdb(
    fs: newFileSystemMemory(),
    database: await syncedSdb.database,
  );
  var mediaSynchronizer = SyncedMediaSdbSynchronizer(
    db: mediaDb,
    source: SyncedMediaSourceMemory(),
    cacheOptions: const SyncedMediaCacheOptions.lru(
      maxCount: 100,
      maxSize: 20 * 1024 * 1024,
    ),
  );
  mediaSynchronizer.startAutoSync(dbSynchronizer.onSynced());

  var mediaId = await mediaDb.addMediaFile(
    file: SyncedMediaFile.from(filename: 'photo.jpg'),
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  await dbSynchronizer.sync();
  await mediaSynchronizer.lazySync();

  var bytes = await mediaSynchronizer.readMediaBytes(mediaId);
  var url = await mediaSynchronizer.getMediaUrl(mediaId);
  print('${bytes.length} bytes, url $url');
  print(await mediaSynchronizer.getCacheStat());

  await mediaSynchronizer.close();
  await dbSynchronizer.close();
  await syncedSdb.close();
}
```

Firebase Storage source with a public url:

```dart
import 'package:tekaly_sdb_synced_media/synced_media_storage.dart';
import 'package:tekartik_firebase_storage/storage.dart';

SyncedMediaSource mediaSource(FirebaseStorage storage) =>
    SyncedMediaSourceStorage(
      storage: storage,
      rootPath: 'app/my_app/media',
      cacheControl: syncedMediaStorageCacheControlImmutable,
      urlBuilder: syncedMediaStoragePublicUrlBuilder(),
    );
```

Api in process (tests, in memory) and the matching server side handler:

```dart
import 'package:tekaly_sdb_synced_media/synced_media.dart';

/// Server: plug it into your api handler.
Future<Map<String, Object?>?> handleMediaCommand(
  SyncedMediaApiService service,
  String command,
  Map<String, Object?> request,
) async {
  if (!service.handles(command)) {
    return null;
  }
  return await service.handle(command, request);
}

SyncedMediaSource inMemoryApiSource() => SyncedMediaSourceApi(
  client: SyncedMediaApiClientLocal(
    service: SyncedMediaApiService(
      source: SyncedMediaSourceMemory(),
      accessCheck: (command, ref) {
        if (command == SyncedMediaApi.commandDelete) {
          throw SyncedMediaApiException('read only');
        }
      },
    ),
  ),
);
```
