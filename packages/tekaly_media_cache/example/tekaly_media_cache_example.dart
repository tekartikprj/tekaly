import 'package:fs_shim/fs.dart';
import 'package:tekaly_media_cache/tekaly_media_cache.dart';

Future<void> main() async {
  var dir = Directory('.local/simple');
  await dir.delete(recursive: true);
  var mediaCache = TekalyMediaCache(rootDirectory: dir.absolute);
  mediaCache
      .onMedia(TekalyMediaKey.name('test_info'))
      .listen((event) => print('Event: $event'));
  await mediaCache.cacheMedia(
    TekalyMediaKey.name('test'),
    Uri.parse('https://www.tekartik.com'),
  );
  await mediaCache.cacheMedia(
    TekalyMediaKey.name('test_info'),
    Uri.parse('https://www.google.com'),
  );
  var content = await mediaCache.getMedia(TekalyMediaKey.name('test'));
  print(
    'Content: ${content?.info.name} ${content?.info.type} ${content?.info.size}',
  );

  await mediaCache.cacheMedia(
    TekalyMediaKey.name('test_info'),
    Uri.parse('https://tekartik-info.web.app'),
  );

  await mediaCache.clean();
}
