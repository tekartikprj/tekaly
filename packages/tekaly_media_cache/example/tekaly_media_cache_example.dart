// ignore_for_file: avoid_print

// A media cache in `.local/media_cache_example` (database and files):
// `dart run example/tekaly_media_cache_example.dart` twice, the second run
// reads the cached file without fetching it.
import 'dart:convert';

import 'package:fs_shim/fs_shim.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekartik_app_sembast/sembast.dart';

/// A sembast factory (tekartik_app_sembast, sqflite ffi on io) keeping its
/// databases in [rootDirectory] (absolute), the current directory by
/// default.
DatabaseFactory getSembastDatabaseFactory({Directory? rootDirectory}) {
  rootDirectory ??= fileSystemDefault.currentDirectory;
  return getDatabaseFactory(rootPath: rootDirectory.path);
}

Future<void> main() async {
  // Absolute: the database factory and the cache share the folder.
  var dir = Directory('.local/media_cache_example').absolute;
  var mediaCache = TekalyMediaCache(
    databaseFactory: getSembastDatabaseFactory(rootDirectory: dir),
    rootDirectory: dir,
  );
  var key = TekalyMediaKey.name('connected');
  // The cached content, now (if any) and each time it is cached.
  var subscription = mediaCache
      .onMedia(key)
      .listen((content) => print('onMedia: ${content.info}'));
  try {
    if (await mediaCache.isMediaCached(key)) {
      print('already cached');
    } else {
      await mediaCache.cacheMedia(
        TekalyMediaSourceInfo.parse(
          key,
          'https://tekartik-test-fixtures.web.app/http/connected.json',
          type: 'application/json',
        ),
      );
    }
    var content = await mediaCache.getMedia(key);
    if (content != null) {
      print('${content.info.name}: ${utf8.decode(content.bytes)}');
    }
  } catch (e) {
    // Offline the first time.
    print('error: $e');
  }
  await subscription.cancel();
  await mediaCache.close();
}
