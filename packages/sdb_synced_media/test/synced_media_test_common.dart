import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';

/// Source wrapper counting the calls, with an optional network url.
class CountingMediaSource implements SyncedMediaSource {
  final SyncedMediaSource inner;
  final Uri? Function(SyncedMediaFileRef ref)? urlBuilder;
  var addCount = 0;
  var readCount = 0;
  var deleteCount = 0;
  var urlCount = 0;

  CountingMediaSource(this.inner, {this.urlBuilder});

  @override
  Future<void> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  }) {
    addCount++;
    return inner.addMediaFile(file: file, bytes: bytes);
  }

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) {
    deleteCount++;
    return inner.deleteMediaFile(ref);
  }

  @override
  Future<Uri?> getMediaUrl(SyncedMediaFileRef ref) async {
    urlCount++;
    return urlBuilder?.call(ref) ?? await inner.getMediaUrl(ref);
  }

  @override
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref) {
    readCount++;
    return inner.readMediaFileBytes(ref);
  }
}

/// Content of [size] bytes.
Uint8List bytesOfSize(int size, {int value = 1}) =>
    Uint8List.fromList(List.filled(size, value));

/// Schema of a synced sdb holding the default media stores.
final mediaSyncedSdbOptions = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [
        ...syncedMediaSdbStoresDefault.schemaStores,
        ...syncedSdbMetaSchema.stores,
      ],
    ),
  ),
);

/// A client: a synced sdb holding the media records, synchronized with
/// [source], and its media synchronized with [mediaSource].
class MediaClient {
  final SyncedSdb syncedSdb;
  final SyncedSdbSynchronizer dbSynchronizer;
  final SyncedMediaSdb mediaDb;
  final SyncedMediaSdbSynchronizer mediaSynchronizer;

  MediaClient._(
    this.syncedSdb,
    this.dbSynchronizer,
    this.mediaDb,
    this.mediaSynchronizer,
  );

  static Future<MediaClient> open({
    required SyncedSource source,
    required SyncedMediaSource mediaSource,
    SyncedMediaCacheOptions cacheOptions = const SyncedMediaCacheOptions.all(),
    bool storeUrl = false,
  }) async {
    var syncedSdb = SyncedSdb.newInMemory(options: mediaSyncedSdbOptions);
    var dbSynchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
    var mediaDb = SyncedMediaSdb(
      fs: newFileSystemMemory(),
      database: await syncedSdb.database,
    );
    var mediaSynchronizer = SyncedMediaSdbSynchronizer(
      db: mediaDb,
      source: mediaSource,
      cacheOptions: cacheOptions,
      storeUrl: storeUrl,
    );
    return MediaClient._(syncedSdb, dbSynchronizer, mediaDb, mediaSynchronizer);
  }

  /// Database sync, media sync then database sync again (uploaded flags).
  Future<SyncedSyncStat> syncAll() async {
    await dbSynchronizer.sync();
    var stat = await mediaSynchronizer.sync();
    await dbSynchronizer.sync();
    return stat;
  }

  Future<String> addMedia(String filename, Uint8List bytes) =>
      mediaDb.addMediaFile(
        file: SyncedMediaFile.from(filename: filename),
        bytes: bytes,
      );

  Future<bool> isLocal(String fileId) async =>
      (await mediaDb.getMediaFileStatus(fileId))?.isLocal ?? false;

  Future<void> close() async {
    await mediaSynchronizer.close();
    await dbSynchronizer.close();
    await syncedSdb.close();
  }
}
