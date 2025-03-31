import 'package:fs_shim/fs.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekaly_media_cache/src/media_cache.dart'
    show TekalyMediaCachePrvExt;
import 'package:tekaly_media_cache/src/media_cache_db.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:test/test.dart';

void main() {
  //debugTekalyMediaCache = devWarning(true);
  var dir = Directory('.local/test');
  test('key', () {
    expect(TekalyMediaKey.name('test').toString(), 'Key(test)');
  });
  test('auto clean', () async {
    var dir = Directory('.local/test/auto_clean');
    var mediaCache = TekalyMediaCache(
      rootDirectory: dir.absolute,
      options: TekalyMediaCacheOptions(
        firstAutoCleanDuration: const Duration(milliseconds: 300),
        nextAutoCleanDuration: const Duration(milliseconds: 500),
      ),
    );
    expect(mediaCache.cleanCount, 0);
    await sleep(400);
    expect(mediaCache.cleanCount, 1);
    await sleep(500);
    expect(mediaCache.cleanCount, 2);

    await mediaCache.close();
  });
  group('cache', () {
    late TekalyMediaCache mediaCache;
    setUp(() async {
      mediaCache = TekalyMediaCache(rootDirectory: dir.absolute);
      await mediaCache.clear();
    });
    test('cacheContent delete file', () async {
      var content = utf8.encode('hello');
      var key = TekalyMediaKey.name('test_key');
      await mediaCache.cacheContent(
        TekalyMediaContent(
          info: TekalyMediaInfo(
            key: key,
            name: 'test_name',
            type: 'test_type',
            size: content.length,
          ),
          bytes: content,
        ),
      );
      var readContent = (await mediaCache.getMedia(key))!;
      expect(readContent.key, key);
      expect(readContent.bytes, content);
      expect(readContent.info.type, 'test_type');
      expect(readContent.info.name, 'test_name');
      await mediaCache.clean();
      expect(await mediaCache.isMediaCached(key), isTrue);
      await mediaCache.mediaDirectory.file('test_name').delete();
      expect(await mediaCache.isMediaCached(key), isTrue);

      expect(await mediaCache.getMedia(key), isNull);
      await mediaCache.clean();
      expect(await mediaCache.isMediaCached(key), isFalse);
    });
    test('cacheContent delete dbEntry', () async {
      var content = utf8.encode('hello');
      var key = TekalyMediaKey.name('test_key');
      await mediaCache.cacheContent(
        TekalyMediaContent(
          info: TekalyMediaInfo(
            key: key,
            name: 'test_name',
            type: 'test_type',
            size: content.length,
          ),
          bytes: content,
        ),
      );
      var readContent = (await mediaCache.getMedia(key))!;
      expect(readContent.key, key);
      expect(readContent.bytes, content);
      expect(readContent.info.type, 'test_type');
      expect(readContent.info.name, 'test_name');
      await mediaCache.clean();
      var file = mediaCache.mediaDirectory.file('test_name');
      expect(await mediaCache.isMediaCached(key), isTrue);
      expect(await file.exists(), isTrue);
      await dbMediaStore.delete(await mediaCache.database);
      expect(await mediaCache.isMediaCached(key), isFalse);
      expect(await file.exists(), isTrue);
      expect(await mediaCache.getMedia(key), isNull);

      await mediaCache.clean();
      expect(await file.exists(), isFalse);
      expect(await mediaCache.isMediaCached(key), isFalse);
    });

    tearDown(() async {
      await mediaCache.close();
    });
  });
}
