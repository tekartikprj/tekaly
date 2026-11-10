---
name: tekaly-media-cache-cache-media
description: >-
  Use when caching remote media files (images, audio, assets) locally by key
  with tekaly_media_cache (TekalyMediaCache, TekalyMediaSourceInfo,
  TekalyMediaKey), including custom fetchers and cache cleaning.
---

# Local media cache (tekaly_media_cache)

`TekalyMediaCache` stores media bytes as files under a root directory
(`fs_shim`) and their info (name, mime type, size, caching time) in a
sembast database of the same directory, keyed by a `TekalyMediaKey`.

## Guidelines

* Import `package:tekaly_media_cache/media_cache.dart`. Create one cache per
  app with `TekalyMediaCache(databaseFactory:, rootDirectory:, options:)`:
  a sembast `DatabaseFactory` (`getDatabaseFactory(rootPath:)` from
  `tekartik_app_sembast` or `tekartik_app_flutter_sembast`) and a `fs_shim`
  `Directory` dedicated to the cache (it holds the database and a media
  folder). Give both the same absolute folder: a relative `rootPath` is
  resolved under the factory's own databases folder, not under the current
  directory. `close()` it when done. Tests: `newDatabaseFactoryMemory()`
  (sembast) and `newFileSystemMemory().directory('/cache')` (fs_shim).
* Identify a media with `TekalyMediaKey.name('stable-id')` and describe where
  it comes from with `TekalyMediaSourceInfo.parse(key, url, name:, type:)`
  (`name` is the media name, defaults to the url last segment; `type` the
  mime type). The cached file is named from the key, so two keys never share
  a file even with the same name.
* `cacheMedia(src)` fetches (http by default) and stores the media, returning
  its `TekalyMediaContent` (`info` + `bytes`); `getMedia(key)` returns the
  cached content or null; `isMediaCached(key)` checks without reading;
  `onMedia(key)` streams the content when it becomes available or changes
  (bind a UI to it and call `cacheMedia` when it is missing).
* `fetchMedia(src)` fetches without caching; `cacheContent(TekalyMediaContent
  (info: TekalyMediaInfo(key:, name:, type:, size:), bytes:))` stores bytes
  you already have.
* Provide a `TekalyMediaFetcher` in `TekalyMediaCacheOptions(mediaFetcher:)`
  when downloads need authentication, an asset bundle or a custom client.
* Cleaning: `deleteMedia(key)`, `deleteOldMedias(keepCount:)` (keeps the 100
  most recently cached by default), `clean()` (removes the files without
  record and the records without file; scheduled automatically after
  `firstAutoCleanDuration`, 5 s, then every `nextAutoCleanDuration`, 15 s),
  `clear()` wipes everything (the cache stays usable, the automatic clean
  goes on since 2026-11-10).
* `isMediaCached(key)` only checks the record; `getMedia(key)` returns null
  and drops the record when the file is gone (`onMedia` gets an error).
* `initSession()` gives a `TekalyMediaCacheSession` to remember the source
  info of the keys used on a screen (`addSource` / `getSource`).
* `debugTekalyMediaCache = true` logs the cache activity.

## Examples

```dart
import 'package:fs_shim/fs_shim.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekartik_app_sembast/sembast.dart';

Future<void> main() async {
  // Absolute: the database factory and the cache share the folder.
  var dir = Directory('.local/media_cache').absolute;
  var mediaCache = TekalyMediaCache(
    databaseFactory: getDatabaseFactory(rootPath: dir.path),
    rootDirectory: dir,
    options: TekalyMediaCacheOptions(
      nextAutoCleanDuration: const Duration(minutes: 5),
    ),
  );

  var key = TekalyMediaKey.name('logo');
  var subscription = mediaCache.onMedia(key).listen((content) {
    print('${content.info.name}: ${content.bytes.length} byte(s)');
  });

  if (!await mediaCache.isMediaCached(key)) {
    await mediaCache.cacheMedia(
      TekalyMediaSourceInfo.parse(
        key,
        'https://tekartik.com/packages/tekartik_www_home/img/logo_dark_800x182.png',
        name: 'logo.png',
        type: 'image/png',
      ),
    );
  }
  var content = await mediaCache.getMedia(key);
  print(content?.info.type);

  await mediaCache.deleteOldMedias(keepCount: 50);
  await subscription.cancel();
  await mediaCache.close();
}
```

### Custom fetcher

```dart
import 'dart:typed_data';

import 'package:tekaly_media_cache/media_cache.dart';

class AuthMediaFetcher implements TekalyMediaFetcher {
  final Future<Uint8List> Function(Uri uri) download;
  AuthMediaFetcher(this.download);

  @override
  Future<Uint8List> fetch(TekalyMediaSourceInfo src) => download(src.uri);
}
```
