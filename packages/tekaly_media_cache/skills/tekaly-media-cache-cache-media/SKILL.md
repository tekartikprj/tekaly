---
name: tekaly-media-cache-cache-media
description: >-
  Use when caching remote media files (images, audio, assets) locally by key
  with tekaly_media_cache (TekalyMediaCache, TekalyMediaSourceInfo,
  TekalyMediaKey), including custom fetchers and cache cleaning.
---

# Local media cache (tekaly_media_cache)

`TekalyMediaCache` stores media bytes as files under a root directory
(`fs_shim`) and their info (name, mime type, size, last access) in a sembast
database, keyed by a `TekalyMediaKey`.

## Guidelines

* Import `package:tekaly_media_cache/media_cache.dart`. Create one cache per
  app with `TekalyMediaCache(databaseFactory:, rootDirectory:, options:)`:
  a sembast `DatabaseFactory` (`getDatabaseFactory(rootPath:)` from
  `tekartik_app_sembast` or `tekartik_app_flutter_sembast`) and a `fs_shim`
  `Directory` dedicated to the cache (it holds the database and a media
  folder). `close()` it when done.
* Identify a media with `TekalyMediaKey.name('stable-id')` and describe where
  it comes from with `TekalyMediaSourceInfo.parse(key, url, name:, type:)`
  (`name` is the local file name, defaults to the url last segment; `type`
  the mime type).
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
  most recently used by default), `clean()` (scheduled automatically after
  `firstAutoCleanDuration` then every `nextAutoCleanDuration`), `clear()`
  wipes everything.
* `initSession()` gives a `TekalyMediaCacheSession` to remember the source
  info of the keys used on a screen (`addSource` / `getSource`).
* `debugTekalyMediaCache = true` logs the cache activity.

## Examples

```dart
import 'package:fs_shim/fs_shim.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekartik_app_sembast/sembast.dart';

Future<void> main() async {
  var dir = Directory('.local/media_cache');
  var mediaCache = TekalyMediaCache(
    databaseFactory: getDatabaseFactory(rootPath: dir.path),
    rootDirectory: dir,
    options: TekalyMediaCacheOptions(
      nextAutoCleanDuration: const Duration(minutes: 5),
    ),
  );

  var key = TekalyMediaKey.name('logo');
  mediaCache.onMedia(key).listen((content) {
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
