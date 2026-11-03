import 'dart:async';
import 'dart:typed_data';

import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';
import 'package:test/test.dart';

import 'synced_media_test_common.dart';

/// Source whose uploads can be held ([gate]) or fail ([error]).
class _GatedMediaSource with SyncedMediaSourceMixin {
  final SyncedMediaSource inner;
  Completer<void>? gate;
  Error? error;

  _GatedMediaSource(this.inner);

  @override
  Future<void> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  }) async {
    var error = this.error;
    if (error != null) {
      throw error;
    }
    await gate?.future;
    await inner.addMediaFile(file: file, bytes: bytes);
  }

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) =>
      inner.deleteMediaFile(ref);

  @override
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref) =>
      inner.readMediaFileBytes(ref);
}

void main() {
  late SyncedSourceMemory source;
  late SyncedMediaSourceMemory memorySource;
  late _GatedMediaSource mediaSource;
  var clients = <MediaClient>[];

  setUp(() {
    source = SyncedSourceMemory();
    memorySource = SyncedMediaSourceMemory();
    mediaSource = _GatedMediaSource(memorySource);
  });
  tearDown(() async {
    mediaSource.gate?.complete();
    for (var client in clients) {
      await client.close();
    }
    clients.clear();
    await source.close();
  });

  Future<MediaClient> open({
    bool uploadBeforeSyncUp = true,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    var client = await MediaClient.open(
      source: source,
      mediaSource: mediaSource,
    );
    if (uploadBeforeSyncUp) {
      client.mediaSynchronizer.uploadBeforeSyncUp(
        client.dbSynchronizer,
        timeout: timeout,
      );
    }
    clients.add(client);
    return client;
  }

  Future<int?> lastChangeId() async =>
      (await source.getMetaInfo())?.lastChangeId.v;

  test('without it, a new media record is pushed twice', () async {
    var a = await open(uploadBeforeSyncUp: false);
    await a.addMedia('1.bin', bytesOfSize(10));
    expect(await a.syncAll(), SyncedSyncStat(remoteCreatedCount: 1));
    expect(await lastChangeId(), 2);
  });

  test('a new media record is pushed once, uploaded', () async {
    var a = await open();
    var b = await open(uploadBeforeSyncUp: false);
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    expect(
      await a.dbSynchronizer.sync(),
      SyncedSyncStat(remoteCreatedCount: 1),
    );
    expect(memorySource.paths, hasLength(1));
    expect(await lastChangeId(), 1);
    // Nothing left for the media sync and the next push.
    expect(await a.syncAll(), SyncedSyncStat());
    expect(await lastChangeId(), 1);

    // The other client gets it uploaded.
    await b.dbSynchronizer.sync();
    expect((await b.mediaDb.getMediaFileRecord(id))!.isUploaded, isTrue);
    expect(await b.syncAll(), SyncedSyncStat(localCreatedCount: 1));
    expect(await b.mediaDb.readMediaFileBytes(id), bytesOfSize(10));
  });

  test('auto sync', () async {
    var a = await open();
    a.mediaSynchronizer.startAutoSync(a.dbSynchronizer.onSynced());
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    await a.dbSynchronizer.sync();
    await a.mediaSynchronizer.lazySync();
    await a.dbSynchronizer.sync();
    expect(await lastChangeId(), 1);
    expect((await a.mediaDb.getMediaFileRecord(id))!.isUploaded, isTrue);
  });

  test('a slow upload does not hold the push', () async {
    var a = await open(timeout: const Duration(milliseconds: 50));
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    var gate = mediaSource.gate = Completer<void>();
    // Pushed not uploaded after the timeout
    expect(
      await a.dbSynchronizer.sync(),
      SyncedSyncStat(remoteCreatedCount: 1),
    );
    expect(await lastChangeId(), 1);
    expect(memorySource.paths, isEmpty);

    gate.complete();
    mediaSource.gate = null;
    // Waits for the running upload, nothing left to upload.
    expect(await a.mediaSynchronizer.sync(), SyncedSyncStat());
    expect(memorySource.paths, hasLength(1));
    expect(
      await a.dbSynchronizer.sync(),
      SyncedSyncStat(remoteUpdatedCount: 1),
    );
    expect(await lastChangeId(), 2);
    expect((await a.mediaDb.getMediaFileRecord(id))!.isUploaded, isTrue);
  });

  test('an upload error does not fail the push', () async {
    var a = await open();
    var id = await a.addMedia('1.bin', bytesOfSize(10));
    mediaSource.error = StateError('upload failed');
    expect(
      await a.dbSynchronizer.sync(),
      SyncedSyncStat(remoteCreatedCount: 1),
    );
    expect(memorySource.paths, isEmpty);
    expect((await a.mediaDb.getMediaFileRecord(id))!.isUploaded, isFalse);

    // Retried before the next push.
    mediaSource.error = null;
    expect(
      await a.dbSynchronizer.sync(),
      SyncedSyncStat(remoteUpdatedCount: 1),
    );
    expect(memorySource.paths, hasLength(1));
    expect(await lastChangeId(), 2);
    expect((await a.mediaDb.getMediaFileRecord(id))!.isUploaded, isTrue);
  });

  test('closed, no upload before the push', () async {
    var a = await open();
    await a.addMedia('1.bin', bytesOfSize(10));
    await a.mediaSynchronizer.close();
    await a.dbSynchronizer.sync();
    expect(memorySource.paths, isEmpty);
  });
}
