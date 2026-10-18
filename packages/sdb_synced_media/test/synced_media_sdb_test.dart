import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';
import 'package:test/test.dart';

void main() {
  late SyncedMediaSdb db;
  late SdbDatabase sdbDb;
  late final fs = db.fs;
  final stores = syncedMediaSdbStoresDefault;
  setUp(() async {
    sdbDb = await newSdbFactoryMemory().openDatabase(
      'test',
      options: SdbOpenDatabaseOptions(
        schema: SdbDatabaseSchema(stores: stores.schemaStores),
      ),
    );
    db = SyncedMediaSdb(fs: newFileSystemMemory(), database: sdbDb);
  });
  tearDown(() async {
    await sdbDb.close();
  });

  Future<SdbSyncedMediaFileStatus?> getStatus(String fileId) =>
      stores.statusStore.record(fileId).get(db.database);

  test('stores', () {
    expect(stores.mediaStore.name, 'media');
    expect(stores.statusStore.name, 'local_media_status');
    var custom = SyncedMediaSdbStores(mediaStoreName: 'image');
    expect(custom.statusStore.name, 'local_image_status');
    expect(
      () => SyncedMediaSdbStores(statusStoreName: 'image_status'),
      throwsArgumentError,
    );
  });

  test('write/read/delete/purge', () async {
    var content = Uint8List.fromList([1, 2, 3]);
    var fileId = await db.addMediaFile(
      bytes: content,
      file: SyncedMediaFile.from(filename: 'test.webp', type: 'image/webp'),
    );
    var status = (await getStatus(fileId))!;
    expect(status.isLocal, isTrue);
    expect(status.isRemote, isFalse);
    expect(status.isDeleted, isFalse);
    expect(status.size.v, 3);
    expect(status.accessed.v, isNotNull);
    expect(await db.readMediaFileBytes(fileId), content);
    var record = (await db.getMediaFileRecord(fileId))!;
    expect(record.id, fileId);
    // The record ref is not hidden by the content ref
    expect(record.ref.key, fileId);
    expect(record.fileRef, SyncedMediaFileRef.fromPath(record.path.v!));
    expect(status.path.v, record.path.v);
    expect(record.toMap(), {
      'type': 'image/webp',
      'size': content.length,
      'filename': 'test.webp',
      // example  'path': 'e1/65/bf/e165bf35b3fa495a81649535b9cfb444_test.webp',
      'path': record.path.v,
      'createdTimestamp': record.createdTimestamp.v,
    });
    expect(record.path.v, endsWith('_test.webp'));
    var file = await db.getMediaFile(fileId);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), content);
    expect(await db.mediaFileExists(fileId), isTrue);
    expect(
      await db.getCacheStat(),
      const SyncedMediaCacheStat(count: 1, size: 3, pendingCount: 1),
    );
    await db.deleteMediaFile(fileId);
    status = (await getStatus(fileId))!;
    expect(status.isLocal, isFalse);
    expect(status.isRemote, isFalse);
    expect(status.isDeleted, isTrue);
    expect((await db.getMediaFileRecord(fileId))!.deleted.v, isTrue);
    expect(await file.exists(), isFalse);
    expect(await db.fileIdsToPurge(), [fileId]);
    expect(
      await db.getCacheStat(),
      const SyncedMediaCacheStat(count: 0, size: 0),
    );
    await db.purgeMediaFile(fileId);
    expect(await db.getMediaFileRecord(fileId), isNull);
    expect(await getStatus(fileId), isNull);
  });

  test('getAllRecords/onMediaFiles', () async {
    var content = Uint8List.fromList([1, 2, 3]);
    await db.addMediaFile(
      bytes: content,
      file: SyncedMediaFile.from(filename: 'test1.webp', type: 'image/webp'),
    );
    var id2 = await db.addMediaFile(
      bytes: content,
      file: SyncedMediaFile.from(filename: 'test2.webp', type: 'image/webp'),
    );
    expect(await db.getAllRecords(), hasLength(2));
    expect(await db.onMediaFiles().first, hasLength(2));
    expect((await db.onMediaFile(id2).first)!.originalFilename.v, 'test2.webp');
    expect((await db.onMediaFileStatus(id2).first)!.isLocal, isTrue);
  });

  test('file system check', () async {
    var content = Uint8List.fromList([1, 2, 3, 4]);
    var fileId = await db.addMediaFile(
      bytes: content,
      file: SyncedMediaFile.from(filename: 'test_fs.webp', type: 'image/webp'),
    );
    var record = (await db.getMediaFileRecord(fileId))!;
    expect(await fs.file(fs.path.normalize(record.path.v!)).exists(), isTrue);
  });

  test('markRemoteDeleted', () async {
    var fileId = await db.addMediaFile(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      file: SyncedMediaFile.from(filename: 'test_fs.webp', type: 'image/webp'),
    );
    await db.markRemoteDeleted(fileId);
    var status = (await getStatus(fileId))!;
    expect(status.isLocal, isTrue);
    expect(status.isRemote, isFalse);
    expect(status.isDeleted, isTrue);
    expect(await db.fileIdsToDeleteLocally(), [fileId]);
  });

  test('invalid path from a synced record', () async {
    await stores.mediaStore
        .record('evil')
        .put(
          db.database,
          SdbSyncedMediaFile()
            ..path.v = '../outside.bin'
            ..uploaded.v = true,
        );
    expect(
      () => db.localFile('../outside.bin'),
      throwsA(isA<SyncedMediaSdbException>()),
    );
    await expectLater(
      () => db.getMediaFile('evil'),
      throwsA(isA<SyncedMediaSdbException>()),
    );
    // Nothing to delete locally
    await db.deleteMediaFile('evil');
    expect((await db.getMediaFileRecord('evil'))!.isDeleted, isTrue);
  });

  test('media file', () {
    var file = SyncedMediaFile.from(filename: '/some/dir/My Photo é.JPG');
    expect(file.originalFilename, 'My Photo é.JPG');
    expect(file.type, 'image/jpeg');
    expect(file.path, startsWith(file.uid.substring(0, 2)));
    expect(file.path, endsWith('/${file.uid}_my_photo_e.JPG'));
    expect(file.ref, SyncedMediaFileRef.fromPath(file.path));
  });
}
