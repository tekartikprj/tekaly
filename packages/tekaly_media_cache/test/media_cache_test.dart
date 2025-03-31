import 'package:fs_shim/fs.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekaly_media_cache/src/media_cache.dart'
    show TekalyMediaCachePrvExt;
import 'package:tekaly_media_cache/src/media_cache_db.dart' show dbMediaStore;
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
        firstAutoCleanDuration: const Duration(milliseconds: 500),
        nextAutoCleanDuration: const Duration(milliseconds: 1000),
      ),
    );
    expect(mediaCache.cleanCount, 0);
    await sleep(700);
    expect(mediaCache.cleanCount, 1);
    await sleep(1000);
    expect(mediaCache.cleanCount, 2);

    await mediaCache.close();
  });
  group('cache', () {
    late TekalyMediaCache mediaCache;
    setUp(() async {
      mediaCache = TekalyMediaCache(rootDirectory: dir.absolute);
      await mediaCache.clear();
    });
    test('cacheContent onMedia file', () async {
      var content = utf8.encode('hello');
      var key = TekalyMediaKey.name('test_key');
      var completer = Completer<void>();
      var subscription = mediaCache.onMedia(key).listen((event) {
        expect(event.key, key);
        expect(event.bytes, content);
        expect(event.info.type, 'test_type');
        expect(event.info.name, 'test_name');
        completer.complete();
      });

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
      await completer.future;
      subscription.cancel().unawait();
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

    test('cacheContent deleteOldMedia file', () async {
      var content = utf8.encode('hello');
      var key1 = TekalyMediaKey.name('test_key');
      var key2 = TekalyMediaKey.name('test_key2');

      await mediaCache.cacheContent(
        TekalyMediaContent(
          info: TekalyMediaInfo(
            key: key1,
            name: 'test_name',
            type: 'test_type',
            size: content.length,
          ),
          bytes: content,
        ),
      );
      await mediaCache.cacheContent(
        TekalyMediaContent(
          info: TekalyMediaInfo(
            key: key2,
            name: 'test_name2',
            type: 'test_type',
            size: content.length,
          ),
          bytes: content,
        ),
      );
      expect((await mediaCache.getAllMediaInfos()).length, 2);
      await mediaCache.deleteOldMedias(keepCount: 1);
      expect((await mediaCache.getAllMediaInfos()).length, 1);
    });
    test('cacheContent deleteOldMedia file', () async {
      var content = utf8.encode('hello');
      var key1 = TekalyMediaKey.name('test_key');
      var key2 = TekalyMediaKey.name('test_key2');

      await mediaCache.cacheContent(
        TekalyMediaContent(
          info: TekalyMediaInfo(
            key: key1,
            name: 'test_name',
            type: 'test_type',
            size: content.length,
          ),
          bytes: content,
        ),
      );
      await mediaCache.cacheContent(
        TekalyMediaContent(
          info: TekalyMediaInfo(
            key: key2,
            name: 'test_name2',
            type: 'test_type',
            size: content.length,
          ),
          bytes: content,
        ),
      );
      expect((await mediaCache.getAllMediaInfos()).length, 2);
      await mediaCache.deleteMedia(key1);
      expect((await mediaCache.getAllMediaInfos()).length, 1);
    });
    tearDown(() async {
      await mediaCache.close();
    });
  });
}
