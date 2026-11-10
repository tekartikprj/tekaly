# tekaly_media_cache

A local cache of remote media (images, audio, json...) keyed by a stable id:
the bytes are files of a [fs_shim](https://pub.dev/packages/fs_shim)
directory, their info (name, mime type, size, caching time) records of a
[sembast](https://pub.dev/packages/sembast) database in the same directory.
Media are fetched over http by default, or by your own fetcher.

## Getting started

Not on pub.dev, add it as a git dependency:

```yaml
dependencies:
  tekaly_media_cache:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/tekaly_media_cache
```

```dart
import 'package:fs_shim/fs_memory.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_media_cache/media_cache.dart';

Future<void> main() async {
  // In memory here; on io a fs_shim directory and a sembast io factory.
  var cache = TekalyMediaCache(
    databaseFactory: newDatabaseFactoryMemory(),
    rootDirectory: newFileSystemMemory().directory('/media_cache'),
  );
  var key = TekalyMediaKey.name('connected');
  if (!await cache.isMediaCached(key)) {
    await cache.cacheMedia(
      TekalyMediaSourceInfo.parse(
        key,
        'https://tekartik-test-fixtures.web.app/http/connected.json',
        type: 'application/json',
      ),
    );
  }
  var content = await cache.getMedia(key);
  print('${content!.info.name}: ${content.bytes.length} bytes');
  await cache.close();
}
```

A cache on the file system in [example/tekaly_media_cache_example.dart](example/tekaly_media_cache_example.dart).

## Platforms

Pure Dart: io (files and a sembast io/sqflite factory, e.g.
`getDatabaseFactory(rootPath:)` of `tekartik_app_sembast`), web (fs_shim
IndexedDB file system and sembast_web) and memory (tests). The default
fetcher uses `tekartik_app_http` (on the web the media server must allow
CORS).

## What to use

- `TekalyMediaCache(databaseFactory:, rootDirectory:, options:)`: one per
  cache directory, kept open, `close()` when done.
- `TekalyMediaKey.name(id)`: the identity of a media (its file is named
  from it). `TekalyMediaSourceInfo.parse(key, url, name:, type:)`: where it
  comes from (`name` defaults to the last segment of the url).
- `cacheMedia(source)` fetches and stores, `getMedia(key)` reads (null when
  not cached), `isMediaCached(key)`, `onMedia(key)` (a stream of the
  content: the cached one first, then each time it is cached again),
  `getMediaInfo(key)`, `getAllMediaInfos()`.
- `fetchMedia(source)` fetches without storing, `cacheContent(content)`
  stores bytes you already have.
- `TekalyMediaCacheOptions(mediaFetcher:, firstAutoCleanDuration:,
  nextAutoCleanDuration:)`: a `TekalyMediaFetcher` for authenticated or
  non http sources; the automatic `clean()` (5 s after opening, then every
  15 s by default) removes the files without record and the records without
  file.
- `deleteMedia(key)`, `deleteOldMedias(keepCount:)` (keeps the most recently
  cached, 100 by default), `clear()` (everything; the cache stays usable).

## Common pitfalls

- Give the database factory and `rootDirectory` the same absolute folder:
  a relative `rootPath` of `tekartik_app_sembast` is resolved under its own
  databases folder, not under the current directory.
- `isMediaCached` only checks the record: `getMedia` returns null (and drops
  the record) when its file is gone.
- A media cached again under the same key replaces the previous one (same
  file); use distinct keys for distinct contents.
- The whole media is read in memory.

Agent skill:
[tekaly-media-cache-cache-media](skills/tekaly-media-cache-cache-media/SKILL.md).
