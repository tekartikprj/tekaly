# tekaly_sdb_synced_media

Media files (images, audio, any bytes) synchronized next to a synced sdb
(`tekaly_sdb_synced`):

- the media records live in a synced store (`media`) of your `SyncedSdb`, so
  they reach every client through the regular database sync (Firestore, ...);
- the contents are kept in a local file system (`fs_shim`) cache and in a
  remote source (Firebase Storage, or any `SyncedMediaSource`);
- the local cache can keep every content (offline first), the most recently
  read ones within a count and/or size limit (lru), or nothing (network
  only).

Extracted from the festenao media sync (`FestenaoMediaSdb`,
`FestenaoMediaSdbSynchronizer`, `FestenaoMediaSourceFirebase`). The store
names, record fields and content paths are the same, so existing festenao
databases and buckets can switch to it without migration.

## Getting started

A git package (not on pub.dev):

```yaml
dependencies:
  tekaly_sdb_synced_media:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/sdb_synced_media
```

[example/main.dart](example/main.dart) runs two clients in memory: one adds
a media, the other reads it (`dart run example/main.dart`).

Pure Dart: io, web and Flutter. What each needs:

- a `SyncedSdb` holding the media stores (any sdb factory of idb_shim);
- an `fs_shim` file system for the local contents, sandboxed to a folder of
  its own (the media paths are relative to it):
  `fileSystemDefault.sandbox(path: ...)` (`package:fs_shim/fs_shim.dart`:
  io on the VM and Flutter native, IndexedDB on the web). On Flutter mobile,
  give it an absolute folder (the application documents or support
  directory): a relative one resolves against the process folder, not
  writable there. `newFileSystemMemory()` in tests;
- a `SyncedMediaSource`: Firebase Storage (`synced_media_storage.dart`),
  your api, or `SyncedMediaSourceMemory` in tests.

## Usage

```dart
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_media/synced_media_storage.dart';

// The media stores are part of the synced database schema.
var options = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [
        ...syncedMediaSdbStoresDefault.schemaStores,
        ...syncedSdbMetaSchema.stores,
      ],
    ),
  ),
);

var mediaDb = SyncedMediaSdb(fs: fs, database: await syncedSdb.database);
var mediaSynchronizer = SyncedMediaSdbSynchronizer(
  db: mediaDb,
  source: SyncedMediaSourceStorage(
    storage: storage,
    rootPath: 'app/my_app/media',
    cacheControl: syncedMediaStorageCacheControlImmutable,
  ),
  cacheOptions: const SyncedMediaCacheOptions.lru(
    maxCount: 200,
    maxSize: 50 * 1024 * 1024,
  ),
);
// Media sync after each database sync (new/deleted records, uploads).
mediaSynchronizer.startAutoSync(dbSynchronizer.onSynced());
// New contents uploaded before each database push: a new media record goes
// up once, already uploaded (the push waits 10 s at most).
mediaSynchronizer.uploadBeforeSyncUp(dbSynchronizer);

var mediaId = await mediaDb.addMediaFile(
  file: SyncedMediaFile.from(filename: 'photo.jpg'),
  bytes: bytes,
);
// Local if cached, from the source otherwise (kept unless cache none).
var content = await mediaSynchronizer.readMediaBytes(mediaId);
```

`SyncedMediaSdb.readMediaFileBytes` only reads the local content (it throws
when not present), use `SyncedMediaSdbSynchronizer.readMediaBytes` once the
cache is not `all`.

## Sources: direct, api, in memory

Every content access goes through a `SyncedMediaSource` (add, read, delete,
network url), so the same synchronizer works:

| Source | Use |
|---|---|
| `SyncedMediaSourceStorage` | direct Firebase Storage access (client rules, or server credentials) |
| `SyncedMediaSourceApi(client:)` | through an api, the server holding the Storage access |
| `SyncedMediaSourceMemory` | in memory (tests, demo) |
| `SyncedMediaSourceHybrid(readSource:, writeSource:)` | e.g. read directly (public/download urls), write through the api |

The api is transport agnostic: commands (`SyncedMediaApi.commandAdd`,
`commandRead`, `commandDelete`, `commandUrl`) with json requests/responses
(contents base64 encoded, keep them small or read them through urls).

- client: implement `SyncedMediaApiClient.send(command, request)` over your
  transport (tkcms secured api, functions callable, http, rpc);
  `SyncedMediaApiClientLocal(service:)` calls a service in process (tests, in
  memory, or a server using its own api);
- server: `SyncedMediaApiService(source:, accessCheck:, maxSize:)` handles
  the commands (`handles(command)`, `handle(command, request)`) on top of any
  source, typically `SyncedMediaSourceStorage` with server credentials;
  `accessCheck` throws to deny (user rights, path prefix).

```dart
// Server
var service = SyncedMediaApiService(
  source: SyncedMediaSourceStorage(storage: adminStorage, rootPath: root),
  accessCheck: (command, ref) => checkUserRights(command, ref),
  maxSize: 8 * 1024 * 1024,
);
// in the api handler: if (service.handles(command)) return service.handle(command, request);

// Client, without/with api, or in memory
SyncedMediaSource source = SyncedMediaSourceApi(client: myApiClient);
source = SyncedMediaSourceApi(
  client: SyncedMediaApiClientLocal(
    service: SyncedMediaApiService(source: SyncedMediaSourceMemory()),
  ),
);
```

Content paths come from synced records (written by any client), they are
validated everywhere (`syncedMediaIsValidPath`: relative, no `..`): the
local file system, the Storage source and the api service reject the others,
the synchronizer skips them.

## Local cache

| Options | On sync | On read miss | Eviction |
|---|---|---|---|
| `SyncedMediaCacheOptions.all()` (default) | download all | download, keep | never |
| `.lru(maxCount:, maxSize:)` | nothing | download, keep | least recently read above the limits |
| `.lru(..., prefetch: true)` | download newest first while it fits (never evicts) | download, keep | same |
| `.lru()` (no limit) | nothing | download, keep | never (on demand cache) |
| `.none()` | nothing | download, not kept | every uploaded content |

Contents added locally and not uploaded yet are never evicted (they count in
the limits). A content larger than `maxSize` is read but not kept.
`trimCache()` applies the limits (called after each sync and read miss),
`getCacheStat()` gives the local count/size.

## Network urls

`SyncedMediaSdbSynchronizer.getMediaUrl(mediaId)` returns a url to display a
content without downloading it in the app (`Image.network`, html `img`,
audio player), useful with the `none` and `lru` caches:

- **download url** (default of `SyncedMediaSourceStorage`): the Firebase
  client sdk url holding a download token
  (`.../o/<path>?alt=media&token=...`). It is permanent: it stays valid until
  the token is revoked (console) or the file is deleted, and works without
  authentication, bypassing the rules (getting it needs read access).
  Media paths never change (a new media gets a new path) so it never goes
  stale. Admin sdk: none (signed urls expire, 7 days max).
- **public url** (`urlBuilder: syncedMediaStoragePublicUrlBuilder()`): the
  same url without token, computed with no network call. Permanent, but only
  readable if the Storage rules allow unauthenticated reads of the path.
- **redirection** (`urlBuilder: (fileRef) => ...`, sync or async): your own
  stable url, e.g. a hosting rewrite to a function that checks access then
  answers `302` to a fresh download/signed url (with a `Cache-Control`). The
  url never changes even if the bucket, the token or the CDN do, at the cost
  of a function call per uncached load. An async builder can also ask an api
  for the url.

`storeUrl: true` (synchronizer) stores the url in the media record on upload,
so every client gets it from the synced record without asking the source.
Anyone reading the record can then read the content.

## Synchronization

`sync()` = reconcile, sync up, sync down, trim:

- local status per media (`local_media_status`, not synced): `local`,
  `remote`, `deleted` flags (indexed), local path, size, last access;
- reconcile: status for new records (from other clients), local content
  deleted when a record is deleted or purged by another client, lost statuses
  rebuilt;
- up: upload local only contents (record `uploaded` set), delete deleted
  contents from the source then purge the records;
- down: purge contents deleted remotely, download per cache mode.

Differences with the festenao version: the status keeps the local path, size
and last access (cleanup of purged records on other clients, lru); a media
deleted before its upload is purged; `uploaded` is only written once.

Errors: each content is tried on its own. A content the source refuses for
good (above the api `maxSize`, denied by `accessCheck`) does not block the
others: `syncUp()` uploads and deletes the rest, `sync()` still downloads,
then the first error is thrown (`lazySync()` and the auto sync log it); the
refused content stays to upload and is tried again by each sync. A failing
download is handled the same way by `syncDown()`.

## Pitfalls

- `SyncedMediaSdb.readMediaFileBytes` reads the local content only: with an
  `lru` or `none` cache read through the synchronizer (`readMediaBytes`).
- `SyncedMediaSourceStorage.deleteMediaFile` ignores every error (not only a
  missing file): with rules denying the delete, the record is purged and the
  content stays in the bucket.
- `deleteMediaFile(id, purge: true)` deletes the records only: an uploaded
  content stays in the source.
- A content lost locally before its upload (cleared app data) stays to
  upload: each sync logs it, the other clients get a record without content.
- `close()` the synchronizer before closing the database.

Package skill (for AI coding agents, `skills/`): `tekaly-sdb-synced-media`.
