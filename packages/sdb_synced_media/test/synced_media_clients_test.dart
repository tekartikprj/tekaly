import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';
import 'package:test/test.dart';

import 'synced_media_test_common.dart';

void main() {
  late SyncedSourceMemory source;
  late SyncedMediaSourceMemory memorySource;
  late CountingMediaSource mediaSource;
  var clients = <MediaClient>[];

  setUp(() {
    source = SyncedSourceMemory();
    memorySource = SyncedMediaSourceMemory();
    mediaSource = CountingMediaSource(
      memorySource,
      urlBuilder: (ref) => Uri.parse('https://example.com/media/${ref.path}'),
    );
  });
  tearDown(() async {
    for (var client in clients) {
      await client.close();
    }
    clients.clear();
    await source.close();
  });

  Future<MediaClient> open({
    SyncedMediaCacheOptions cacheOptions = const SyncedMediaCacheOptions.all(),
    bool storeUrl = false,
  }) async {
    var client = await MediaClient.open(
      source: source,
      mediaSource: mediaSource,
      cacheOptions: cacheOptions,
      storeUrl: storeUrl,
    );
    clients.add(client);
    return client;
  }

  test('add, download, delete then purge', () async {
    var a = await open();
    var b = await open();
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    expect(await a.syncAll(), SyncedSyncStat(remoteCreatedCount: 1));
    expect(await b.syncAll(), SyncedSyncStat(localCreatedCount: 1));
    expect(await b.mediaDb.readMediaFileBytes(id), bytesOfSize(10));
    var bFile = await b.mediaDb.getMediaFile(id);

    await a.mediaDb.deleteMediaFile(id);
    expect(await a.syncAll(), SyncedSyncStat(remoteDeletedCount: 1));
    expect(memorySource.paths, isEmpty);

    // Purged record: the local content is deleted
    expect(await b.syncAll(), SyncedSyncStat(localDeletedCount: 1));
    expect(await b.mediaDb.getMediaFileRecord(id), isNull);
    expect(await b.mediaDb.getMediaFileStatus(id), isNull);
    expect(await bFile.exists(), isFalse);
  });

  test('deleted record seen before its purge', () async {
    var a = await open();
    var b = await open();
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    await a.syncAll();
    await b.syncAll();
    var bFile = await b.mediaDb.getMediaFile(id);

    await a.mediaDb.deleteMediaFile(id);
    // Only the database is synchronized (deleted flag)
    await a.dbSynchronizer.sync();
    expect(
      await b.syncAll(),
      SyncedSyncStat(localDeletedCount: 1, remoteDeletedCount: 1),
    );
    expect(await bFile.exists(), isFalse);
    expect(memorySource.paths, isEmpty);
    expect(await b.mediaDb.getMediaFileRecord(id), isNull);

    // Deleting again is harmless
    expect(await a.syncAll(), SyncedSyncStat(remoteDeletedCount: 1));
    expect(await a.mediaDb.getMediaFileRecord(id), isNull);
    await b.syncAll();
    expect(await b.mediaDb.getAllRecords(), isEmpty);
  });

  test('record synced before its content', () async {
    var a = await open();
    var b = await open();
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    // Record pushed, content not uploaded yet
    await a.dbSynchronizer.sync();
    expect(await b.syncAll(), SyncedSyncStat());
    expect(await b.isLocal(id), isFalse);
    expect(await b.mediaSynchronizer.getMediaUrl(id), isNull);
    await a.syncAll();
    expect(await b.syncAll(), SyncedSyncStat(localCreatedCount: 1));
    expect(await b.isLocal(id), isTrue);
  });

  test('url', () async {
    var a = await open(storeUrl: true);
    var b = await open(cacheOptions: const SyncedMediaCacheOptions.none());
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    expect(await a.mediaSynchronizer.getMediaUrl(id), isNull);
    await a.syncAll();
    expect(mediaSource.urlCount, 1);
    var path = (await a.mediaDb.getMediaFileRecord(id))!.path.v!;
    var url = Uri.parse('https://example.com/media/$path');
    expect((await a.mediaDb.getMediaFileRecord(id))!.url.v, url.toString());

    await b.syncAll();
    // From the record, the source is not called
    expect(await b.mediaSynchronizer.getMediaUrl(id), url);
    expect(mediaSource.urlCount, 1);
  });

  test('url from the source', () async {
    var a = await open();
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    await a.syncAll();
    expect((await a.mediaDb.getMediaFileRecord(id))!.url.v, isNull);
    var url = await a.mediaSynchronizer.getMediaUrl(id);
    expect(url.toString(), startsWith('https://example.com/media/'));
    // Kept in memory
    expect(await a.mediaSynchronizer.getMediaUrl(id), url);
    expect(mediaSource.urlCount, 1);
  });

  test('auto sync', () async {
    var a = await open();
    var b = await open();
    a.mediaSynchronizer.startAutoSync(a.dbSynchronizer.onSynced());
    b.mediaSynchronizer.startAutoSync(b.dbSynchronizer.onSynced());
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    await a.dbSynchronizer.sync();
    await a.mediaSynchronizer.lazySync();
    expect(memorySource.paths, hasLength(1));
    await a.dbSynchronizer.sync();
    await b.dbSynchronizer.sync();
    await b.mediaSynchronizer.lazySync();
    expect(await b.isLocal(id), isTrue);
  });
}
