// ignore_for_file: avoid_print

import 'package:fs_shim/fs_shim.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekartik_app_sembast/sembast.dart';

DatabaseFactory getSembastDatabaseFactory({Directory? rootDirectory}) {
  rootDirectory ??= fileSystemDefault.currentDirectory;
  return getDatabaseFactory(rootPath: rootDirectory.path);
}

Future<void> main() async {
  var dir = Directory('.local/simple');
  await dir.delete(recursive: true);
  var databaseFactory = getSembastDatabaseFactory(rootDirectory: dir.absolute);
  var mediaCache = TekalyMediaCache(
    databaseFactory: databaseFactory,
    rootDirectory: dir.absolute,
  );
  mediaCache
      .onMedia(TekalyMediaKey.name('test_info'))
      .listen((event) => print('Event: $event'));
  await mediaCache.cacheMedia(
    TekalyMediaSourceInfo.parse(
      TekalyMediaKey.name('test'),
      'https://www.tekartik.com',
    ),
  );
  await mediaCache.cacheMedia(
    TekalyMediaSourceInfo.parse(
      TekalyMediaKey.name('test_info'),
      'https://www.google.com',
    ),
  );
  await mediaCache.cacheMedia(
    TekalyMediaSourceInfo.parse(
      TekalyMediaKey.name('test_image'),
      'https://tekartik.com/packages/tekartik_www_home/img/logo_dark_800x182.png',
    ),
  );
  await mediaCache.cacheMedia(
    TekalyMediaSourceInfo.parse(
      TekalyMediaKey.name('test_image_alt'),
      'https://tekartik.com/packages/tekartik_www_home/img/logo_dark_800x182.png',
      name: 'test_image_alt.png',
    ),
  );
  var content = await mediaCache.getMedia(TekalyMediaKey.name('test'));
  print(
    'Content: ${content?.info.name} ${content?.info.type} ${content?.info.size}',
  );

  await mediaCache.cacheMedia(
    TekalyMediaSourceInfo.parse(
      TekalyMediaKey.name('test_info'),
      'https://tekartik-info.web.app',
    ),
  );

  await mediaCache.dump();
  await mediaCache.clean();
  await mediaCache.close();
}
