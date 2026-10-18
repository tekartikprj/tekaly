import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';
import 'package:test/test.dart';

import 'synced_media_test_common.dart';

void main() {
  late SyncedSourceMemory source;
  late CountingMediaSource mediaSource;
  var clients = <MediaClient>[];

  setUp(() {
    source = SyncedSourceMemory();
    mediaSource = CountingMediaSource(SyncedMediaSourceMemory());
  });
  tearDown(() async {
    for (var client in clients) {
      await client.close();
    }
    clients.clear();
    await source.close();
  });

  Future<MediaClient> open(SyncedMediaCacheOptions cacheOptions) async {
    var client = await MediaClient.open(
      source: source,
      mediaSource: mediaSource,
      cacheOptions: cacheOptions,
    );
    clients.add(client);
    return client;
  }

  group('all', () {
    test('read miss is kept', () async {
      var client = await open(const SyncedMediaCacheOptions.all());
      var id = await client.addMedia('a.bin', bytesOfSize(10));
      await client.syncAll();
      await client.mediaDb.markLocalNotPresent(id);
      expect(await client.isLocal(id), isFalse);
      expect(
        await client.mediaSynchronizer.readMediaBytes(id),
        bytesOfSize(10),
      );
      expect(mediaSource.readCount, 1);
      expect(await client.isLocal(id), isTrue);
      expect(
        await client.mediaSynchronizer.readMediaBytes(id),
        bytesOfSize(10),
      );
      expect(mediaSource.readCount, 1);
      // Never trimmed
      expect(await client.mediaSynchronizer.trimCache(), 0);
    });
  });

  group('lru', () {
    test('maxCount', () async {
      var client = await open(const SyncedMediaCacheOptions.lru(maxCount: 2));
      var synchronizer = client.mediaSynchronizer;
      var id1 = await client.addMedia('1.bin', bytesOfSize(10));
      var id2 = await client.addMedia('2.bin', bytesOfSize(20));
      var id3 = await client.addMedia('3.bin', bytesOfSize(30));
      // Pending uploads are never evicted
      expect(await synchronizer.trimCache(), 0);
      expect(
        await synchronizer.getCacheStat(),
        const SyncedMediaCacheStat(count: 3, size: 60, pendingCount: 3),
      );

      // Once uploaded, the least recently used is evicted
      expect(await client.syncAll(), SyncedSyncStat(remoteCreatedCount: 3));
      expect(await client.isLocal(id1), isFalse);
      expect(await client.isLocal(id2), isTrue);
      expect(await client.isLocal(id3), isTrue);
      expect(
        await synchronizer.getCacheStat(),
        const SyncedMediaCacheStat(count: 2, size: 50),
      );

      // Reading id2 makes id3 the least recently used
      expect(await synchronizer.readMediaBytes(id2), bytesOfSize(20));
      expect(mediaSource.readCount, 0);
      // Read from the source and kept, id3 evicted
      expect(await synchronizer.readMediaBytes(id1), bytesOfSize(10));
      expect(mediaSource.readCount, 1);
      expect(await client.isLocal(id1), isTrue);
      expect(await client.isLocal(id2), isTrue);
      expect(await client.isLocal(id3), isFalse);
      expect(await synchronizer.getCachedMediaFile(id3), isNull);
      expect(
        await (await synchronizer.getCachedMediaFile(id1))!.exists(),
        isTrue,
      );

      // Sync does not download anything
      expect(await client.syncAll(), SyncedSyncStat());
      expect(await client.isLocal(id3), isFalse);
    });

    test('maxSize', () async {
      var client = await open(const SyncedMediaCacheOptions.lru(maxSize: 45));
      var synchronizer = client.mediaSynchronizer;
      var id1 = await client.addMedia('1.bin', bytesOfSize(10));
      var id2 = await client.addMedia('2.bin', bytesOfSize(20));
      var id3 = await client.addMedia('3.bin', bytesOfSize(30));
      await client.syncAll();
      expect(await client.isLocal(id1), isFalse);
      expect(await client.isLocal(id2), isFalse);
      expect(await client.isLocal(id3), isTrue);
      expect(
        await synchronizer.getCacheStat(),
        const SyncedMediaCacheStat(count: 1, size: 30),
      );
      await synchronizer.readMediaBytes(id1);
      expect(
        await synchronizer.getCacheStat(),
        const SyncedMediaCacheStat(count: 2, size: 40),
      );
      // 60 > 45, id3 is the least recently used
      await synchronizer.readMediaBytes(id2);
      expect(await client.isLocal(id1), isTrue);
      expect(await client.isLocal(id2), isTrue);
      expect(await client.isLocal(id3), isFalse);
    });

    test('content larger than maxSize is not kept', () async {
      var client = await open(const SyncedMediaCacheOptions.lru(maxSize: 5));
      var id = await client.addMedia('1.bin', bytesOfSize(10));
      await client.syncAll();
      expect(await client.isLocal(id), isFalse);
      expect(
        await client.mediaSynchronizer.readMediaBytes(id),
        bytesOfSize(10),
      );
      expect(await client.isLocal(id), isFalse);
      await client.mediaSynchronizer.readMediaBytes(id);
      expect(mediaSource.readCount, 2);
    });

    test('no limit, on demand', () async {
      var writer = await open(const SyncedMediaCacheOptions.all());
      var id = await writer.addMedia('1.bin', bytesOfSize(10));
      await writer.syncAll();
      var reader = await open(const SyncedMediaCacheOptions.lru());
      expect(await reader.syncAll(), SyncedSyncStat());
      expect(await reader.isLocal(id), isFalse);
      await reader.mediaSynchronizer.readMediaBytes(id);
      await reader.mediaSynchronizer.readMediaBytes(id);
      expect(mediaSource.readCount, 1);
      expect(await reader.isLocal(id), isTrue);
    });

    test('prefetch maxCount', () async {
      var writer = await open(const SyncedMediaCacheOptions.all());
      var id1 = await writer.addMedia('1.bin', bytesOfSize(10));
      var id2 = await writer.addMedia('2.bin', bytesOfSize(20));
      var id3 = await writer.addMedia('3.bin', bytesOfSize(30));
      await writer.syncAll();

      var reader = await open(
        const SyncedMediaCacheOptions.lru(maxCount: 2, prefetch: true),
      );
      // Newest first
      expect(await reader.syncAll(), SyncedSyncStat(localCreatedCount: 2));
      expect(await reader.isLocal(id1), isFalse);
      expect(await reader.isLocal(id2), isTrue);
      expect(await reader.isLocal(id3), isTrue);
      // Full, nothing more
      expect(await reader.syncAll(), SyncedSyncStat());
      await reader.mediaSynchronizer.readMediaBytes(id1);
      expect(await reader.isLocal(id1), isTrue);
      expect(
        await reader.mediaSynchronizer.getCacheStat(),
        isA<SyncedMediaCacheStat>().having((s) => s.count, 'count', 2),
      );
    });

    test('prefetch maxSize', () async {
      var writer = await open(const SyncedMediaCacheOptions.all());
      var id1 = await writer.addMedia('1.bin', bytesOfSize(10));
      var id2 = await writer.addMedia('2.bin', bytesOfSize(20));
      var id3 = await writer.addMedia('3.bin', bytesOfSize(30));
      await writer.syncAll();

      var reader = await open(
        const SyncedMediaCacheOptions.lru(maxSize: 45, prefetch: true),
      );
      // 30 fits, 20 does not, 10 does
      expect(await reader.syncAll(), SyncedSyncStat(localCreatedCount: 2));
      expect(await reader.isLocal(id1), isTrue);
      expect(await reader.isLocal(id2), isFalse);
      expect(await reader.isLocal(id3), isTrue);
    });
  });

  group('none', () {
    test('upload then read from the source', () async {
      var client = await open(const SyncedMediaCacheOptions.none());
      var synchronizer = client.mediaSynchronizer;
      var id = await client.addMedia('1.bin', bytesOfSize(10));
      // Pending, read locally
      expect(await synchronizer.readMediaBytes(id), bytesOfSize(10));
      expect(mediaSource.readCount, 0);
      expect(await client.syncAll(), SyncedSyncStat(remoteCreatedCount: 1));
      expect(await client.isLocal(id), isFalse);
      expect(
        await synchronizer.getCacheStat(),
        const SyncedMediaCacheStat(count: 0, size: 0),
      );
      expect(await synchronizer.readMediaBytes(id), bytesOfSize(10));
      expect(await synchronizer.readMediaBytes(id), bytesOfSize(10));
      expect(mediaSource.readCount, 2);
      expect(await client.isLocal(id), isFalse);
      expect(await synchronizer.getCachedMediaFile(id), isNull);
    });

    test('reader downloads nothing', () async {
      var writer = await open(const SyncedMediaCacheOptions.all());
      var id = await writer.addMedia('1.bin', bytesOfSize(10));
      await writer.syncAll();
      var reader = await open(const SyncedMediaCacheOptions.none());
      expect(await reader.syncAll(), SyncedSyncStat());
      expect(await reader.mediaDb.getMediaFileRecord(id), isNotNull);
      expect(await reader.isLocal(id), isFalse);
      expect(mediaSource.readCount, 0);
    });
  });
}
