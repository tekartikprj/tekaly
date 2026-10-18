import 'dart:convert';

import 'package:fs_shim/fs_memory.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_media/synced_media_storage.dart';
import 'package:tekartik_firebase_local/firebase_local.dart';
import 'package:tekartik_firebase_storage_fs/storage_fs.dart';
import 'package:test/test.dart';

void main() {
  late SyncedMediaSdb db;
  late SyncedMediaSourceStorage source;
  late SdbDatabase sdbDb;
  late FirebaseStorage firebaseStorage;
  late SyncedMediaSdbSynchronizer synchronizer;

  setUp(() async {
    sdbDb = await newSdbFactoryMemory().openDatabase(
      'test',
      options: SdbOpenDatabaseOptions(
        schema: SdbDatabaseSchema(
          stores: syncedMediaSdbStoresDefault.schemaStores,
        ),
      ),
    );
    db = SyncedMediaSdb(fs: newFileSystemMemory(), database: sdbDb);
    var firebaseLocal = FirebaseLocal();
    var app = firebaseLocal.initializeApp(
      options: FirebaseAppOptions(
        projectId: 'test',
        storageBucket: 'test_bucket',
      ),
    );

    firebaseStorage = newStorageServiceMemory().storage(app);
    source = SyncedMediaSourceStorage(
      storage: firebaseStorage,
      rootPath: 'test_media',
    );
    synchronizer = SyncedMediaSdbSynchronizer(db: db, source: source);
  });
  tearDown(() async {
    await synchronizer.close();
    await sdbDb.close();
    await firebaseStorage.app.delete();
  });

  Future<String> addTextFile() => db.addMediaFile(
    file: SyncedMediaFile.from(filename: 'test.txt'),
    bytes: utf8.encode('test_content'),
  );

  Future<bool> existsRemotely(String fileId) async {
    var record = (await db.getMediaFileRecord(fileId))!;
    return await source.bucket
        .file(source.storagePath(record.fileRef))
        .exists();
  }

  test('nothing', () async {
    expect(await synchronizer.sync(), SyncedSyncStat());
  });
  test('add/delete', () async {
    var id = await addTextFile();
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));
    expect(await existsRemotely(id), isTrue);
    expect((await db.getMediaFileRecord(id))!.isUploaded, isTrue);
    expect(await synchronizer.sync(), SyncedSyncStat());
    var path = (await db.getMediaFileRecord(id))!.path.v!;
    await db.deleteMediaFile(id);
    expect(await db.getMediaFileRecord(id), isNotNull);
    expect(await synchronizer.sync(), SyncedSyncStat(remoteDeletedCount: 1));
    expect(await db.getMediaFileRecord(id), isNull);
    expect(
      await source.bucket
          .file(source.storagePath(SyncedMediaFileRef.fromPath(path)))
          .exists(),
      isFalse,
    );
  });
  test('add/delete before upload', () async {
    var id = await addTextFile();
    await db.deleteMediaFile(id);
    expect(await synchronizer.sync(), SyncedSyncStat());
    expect(await db.getMediaFileRecord(id), isNull);
    expect(await db.getMediaFileStatus(id), isNull);
  });
  test('add then mark as not downloaded', () async {
    var id = await addTextFile();
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));
    await db.markLocalNotPresent(id);
    expect(await synchronizer.sync(), SyncedSyncStat(localCreatedCount: 1));
  });
  test('add then delete remotely', () async {
    var id = await addTextFile();
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));
    await db.markRemoteDeleted(id);
    expect(await db.getMediaFileRecord(id), isNotNull);
    expect(await synchronizer.sync(), SyncedSyncStat(localDeletedCount: 1));
    expect(await db.getMediaFileRecord(id), isNull);
  });
  test('add then sync then delete file and invalidate', () async {
    var id = await addTextFile();
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));

    var file = await db.getMediaFile(id);
    expect(await file.exists(), isTrue);
    await file.delete();
    expect(await file.exists(), isFalse);
    file = await db.getMediaFile(id);
    expect(await file.exists(), isFalse);
    await expectLater(
      () => db.readMediaFileBytes(id),
      throwsA(isA<FileSystemException>()),
    );
    // Read from the source
    expect(utf8.decode(await synchronizer.readMediaBytes(id)), 'test_content');
    expect(await file.exists(), isTrue);
    await file.delete();
    expect(await synchronizer.sync(), SyncedSyncStat());
    await db.markToUpload(id);
    expect(await synchronizer.sync(), SyncedSyncStat(localCreatedCount: 1));
    await db.markStatusCleared(id);
    expect(await synchronizer.sync(), SyncedSyncStat(localCreatedCount: 1));
    expect(await synchronizer.sync(), SyncedSyncStat());
    await db.deleteStatusRecord(id);
    expect(await synchronizer.sync(), SyncedSyncStat(localCreatedCount: 1));
  });
  test('lost status before upload', () async {
    var id = await addTextFile();
    await db.deleteStatusRecord(id);
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));
    expect(await existsRemotely(id), isTrue);
  });
  test('orphan status', () async {
    var id = await addTextFile();
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));
    var file = await db.getMediaFile(id);
    // Purged by another client
    await syncedMediaSdbStoresDefault.mediaStore.record(id).delete(sdbDb);
    expect(await synchronizer.sync(), SyncedSyncStat(localDeletedCount: 1));
    expect(await db.getMediaFileStatus(id), isNull);
    expect(await file.exists(), isFalse);
  });
  test('invalid path from a synced record', () async {
    await syncedMediaSdbStoresDefault.mediaStore
        .record('evil')
        .put(
          sdbDb,
          SdbSyncedMediaFile()
            ..path.v = '../outside.bin'
            ..uploaded.v = true,
        );
    var id = await addTextFile();
    // Skipped, does not block the others
    expect(await synchronizer.sync(), SyncedSyncStat(remoteCreatedCount: 1));
    expect(await existsRemotely(id), isTrue);
    await expectLater(
      () => synchronizer.readMediaBytes('evil'),
      throwsA(anything),
    );
    await db.deleteMediaFile('evil');
    expect(await synchronizer.sync(), SyncedSyncStat());
    expect(await db.getMediaFileRecord('evil'), isNull);
  });
  test('closed', () async {
    await addTextFile();
    await synchronizer.close();
    expect((await synchronizer.sync()).notExecuted, isTrue);
  });
}
