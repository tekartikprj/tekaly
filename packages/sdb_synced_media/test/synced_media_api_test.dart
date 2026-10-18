import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';
import 'package:test/test.dart';

import 'synced_media_test_common.dart';

void main() {
  test('syncedMediaIsValidPath', () {
    expect(syncedMediaIsValidPath('ab/cd/ef/abcdef_test.webp'), isTrue);
    expect(syncedMediaIsValidPath('test.webp'), isTrue);
    for (var path in [
      '',
      '/ab/test.webp',
      '../test.webp',
      'ab/../../test.webp',
      'ab/./test.webp',
      'ab//test.webp',
      'ab\\test.webp',
    ]) {
      expect(syncedMediaIsValidPath(path), isFalse, reason: path);
    }
  });

  group('api', () {
    late SyncedMediaSourceMemory serverSource;
    late SyncedMediaApiService service;
    late SyncedMediaSourceApi apiSource;

    setUp(() {
      serverSource = SyncedMediaSourceMemory();
      service = SyncedMediaApiService(source: serverSource, maxSize: 100);
      apiSource = SyncedMediaSourceApi(
        client: SyncedMediaApiClientLocal(service: service),
      );
    });

    test('add/read/url/delete', () async {
      var file = SyncedMediaFile.from(filename: 'test.webp');
      await apiSource.addMediaFile(file: file, bytes: bytesOfSize(10));
      expect(serverSource.paths, [file.path]);
      expect(await apiSource.readMediaFileBytes(file.ref), bytesOfSize(10));
      // The memory source has no url
      expect(await apiSource.getMediaUrl(file.ref), isNull);
      await apiSource.deleteMediaFile(file.ref);
      expect(serverSource.paths, isEmpty);
      await expectLater(
        () => apiSource.readMediaFileBytes(file.ref),
        throwsA(anything),
      );
    });

    test('url', () async {
      var urlService = SyncedMediaApiService(
        source: CountingMediaSource(
          serverSource,
          urlBuilder: (ref) => Uri.parse('https://example.com/${ref.path}'),
        ),
      );
      var source = SyncedMediaSourceApi(
        client: SyncedMediaApiClientLocal(service: urlService),
      );
      expect(
        await source.getMediaUrl(SyncedMediaFileRef.fromPath('a/b.webp')),
        Uri.parse('https://example.com/a/b.webp'),
      );
    });

    test('invalid', () async {
      for (var path in ['../test.webp', '/test.webp', '']) {
        await expectLater(
          () => apiSource.readMediaFileBytes(SyncedMediaFileRef.fromPath(path)),
          throwsA(isA<SyncedMediaApiException>()),
          reason: path,
        );
      }
      await expectLater(
        () => apiSource.addMediaFile(
          file: SyncedMediaFile.from(filename: 'big.bin'),
          bytes: bytesOfSize(101),
        ),
        throwsA(isA<SyncedMediaApiException>()),
      );
      await expectLater(
        () => service.handle('unknown', {}),
        throwsA(isA<SyncedMediaApiException>()),
      );
      expect(service.handles(SyncedMediaApi.commandRead), isTrue);
      expect(service.handles('unknown'), isFalse);
    });

    test('access check', () async {
      var checkService = SyncedMediaApiService(
        source: serverSource,
        accessCheck: (command, ref) {
          if (command == SyncedMediaApi.commandDelete ||
              !ref.path.startsWith('public/')) {
            throw SyncedMediaApiException('denied $command $ref');
          }
        },
      );
      var source = SyncedMediaSourceApi(
        client: SyncedMediaApiClientLocal(service: checkService),
      );
      var file = SyncedMediaFile(
        uid: 'id',
        originalFilename: 'a.bin',
        type: 'application/octet-stream',
        path: 'public/a.bin',
        size: null,
      );
      await source.addMediaFile(file: file, bytes: bytesOfSize(1));
      expect(await source.readMediaFileBytes(file.ref), bytesOfSize(1));
      await expectLater(
        () => source.deleteMediaFile(file.ref),
        throwsA(isA<SyncedMediaApiException>()),
      );
      await expectLater(
        () => source.readMediaFileBytes(
          SyncedMediaFileRef.fromPath('private/a.bin'),
        ),
        throwsA(isA<SyncedMediaApiException>()),
      );
    });
  });

  group('clients', () {
    late SyncedSourceMemory source;
    late CountingMediaSource bucket;
    late CountingMediaSource apiSource;
    var clients = <MediaClient>[];

    setUp(() {
      source = SyncedSourceMemory();
      // The bucket, readable directly
      bucket = CountingMediaSource(SyncedMediaSourceMemory());
      // Writes through the api
      apiSource = CountingMediaSource(
        SyncedMediaSourceApi(
          client: SyncedMediaApiClientLocal(
            service: SyncedMediaApiService(source: bucket),
          ),
        ),
      );
    });
    tearDown(() async {
      for (var client in clients) {
        await client.close();
      }
      clients.clear();
      await source.close();
    });

    test('write through the api, read directly', () async {
      var hybrid = SyncedMediaSourceHybrid(
        readSource: bucket,
        writeSource: apiSource,
      );
      var a = await MediaClient.open(source: source, mediaSource: hybrid);
      clients.add(a);
      var b = await MediaClient.open(
        source: source,
        mediaSource: hybrid,
        cacheOptions: const SyncedMediaCacheOptions.none(),
      );
      clients.add(b);

      var id = await a.addMedia('1.bin', bytesOfSize(10));
      expect(await a.syncAll(), SyncedSyncStat(remoteCreatedCount: 1));
      expect(apiSource.addCount, 1);
      expect(bucket.addCount, 1);

      await b.syncAll();
      bucket.readCount = 0;
      expect(await b.mediaSynchronizer.readMediaBytes(id), bytesOfSize(10));
      expect(bucket.readCount, 1);
      expect(apiSource.readCount, 0);

      await a.mediaDb.deleteMediaFile(id);
      expect(await a.syncAll(), SyncedSyncStat(remoteDeletedCount: 1));
      expect(apiSource.deleteCount, 1);
      expect(bucket.deleteCount, 1);
    });

    test('all through the api', () async {
      var a = await MediaClient.open(source: source, mediaSource: apiSource);
      clients.add(a);
      var b = await MediaClient.open(source: source, mediaSource: apiSource);
      clients.add(b);
      var id = await a.addMedia('1.bin', bytesOfSize(10));
      await a.syncAll();
      expect(await b.syncAll(), SyncedSyncStat(localCreatedCount: 1));
      expect(await b.mediaDb.readMediaFileBytes(id), bytesOfSize(10));
      expect(apiSource.readCount, 1);
      expect(bucket.readCount, 1);
    });
  });
}
