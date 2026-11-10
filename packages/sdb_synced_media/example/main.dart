// ignore_for_file: avoid_print

// A media added on one client, read on another, all in memory: run it with
// `dart run example/main.dart`.
import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';

/// The synced database schema: the media stores next to the sync meta.
final options = SyncedSdbOptions(
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

/// One client: its synced database and its media.
class Client {
  final SyncedSdb syncedSdb;
  final SyncedSdbSynchronizer dbSynchronizer;
  final SyncedMediaSdb mediaDb;
  final SyncedMediaSdbSynchronizer mediaSynchronizer;

  Client._(
    this.syncedSdb,
    this.dbSynchronizer,
    this.mediaDb,
    this.mediaSynchronizer,
  );

  static Future<Client> open(
    SyncedSource source,
    SyncedMediaSource mediaSource,
  ) async {
    var syncedSdb = SyncedSdb.newInMemory(options: options);
    var dbSynchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
    var mediaDb = SyncedMediaSdb(
      // io: fileSystemDefault.sandbox(path: <app folder>/media)
      fs: newFileSystemMemory(),
      database: await syncedSdb.database,
    );
    var mediaSynchronizer = SyncedMediaSdbSynchronizer(
      db: mediaDb,
      source: mediaSource,
      cacheOptions: const SyncedMediaCacheOptions.lru(
        maxCount: 100,
        maxSize: 20 * 1024 * 1024,
      ),
    );
    // New contents uploaded before each database push.
    mediaSynchronizer.uploadBeforeSyncUp(dbSynchronizer);
    return Client._(syncedSdb, dbSynchronizer, mediaDb, mediaSynchronizer);
  }

  /// What the auto sync does (`startAutoSync(dbSynchronizer.onSynced())`).
  Future<void> sync() async {
    await dbSynchronizer.sync();
    await mediaSynchronizer.sync();
  }

  Future<void> close() async {
    await mediaSynchronizer.close();
    await dbSynchronizer.close();
    await syncedSdb.close();
  }
}

Future<void> main() async {
  // The shared database source and media source (Firestore and Firebase
  // Storage in an app).
  var source = SyncedSourceMemory();
  var mediaSource = SyncedMediaSourceMemory();

  var writer = await Client.open(source, mediaSource);
  var mediaId = await writer.mediaDb.addMediaFile(
    file: SyncedMediaFile.from(filename: 'photo.jpg'),
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  await writer.sync();
  print('uploaded: ${mediaSource.paths}');

  var reader = await Client.open(source, mediaSource);
  await reader.sync();
  // Local if cached, from the source otherwise.
  var bytes = await reader.mediaSynchronizer.readMediaBytes(mediaId);
  print('read ${bytes.length} bytes');
  print(await reader.mediaSynchronizer.getCacheStat());

  await writer.close();
  await reader.close();
}
