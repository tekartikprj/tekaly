import 'dart:typed_data';

import 'package:tekaly_sdb_synced_media/synced_media_storage.dart';
import 'package:tekartik_firebase_local/firebase_local.dart';
import 'package:tekartik_firebase_storage/utils/link.dart';
import 'package:tekartik_firebase_storage_fs/storage_fs.dart';
import 'package:test/test.dart';

void main() {
  group('synced_media_source_storage', () {
    late SyncedMediaSourceStorage source;
    late FirebaseStorage storage;
    late FirebaseApp app;

    setUp(() {
      app = FirebaseLocal().initializeApp(
        options: FirebaseAppOptions(
          projectId: 'test',
          storageBucket: 'test_bucket',
        ),
      );
      storage = newStorageServiceMemory().storage(app);
      source = SyncedMediaSourceStorage(
        storage: storage,
        rootPath: 'test_media',
        cacheControl: syncedMediaStorageCacheControlImmutable,
      );
    });
    tearDown(() async {
      await app.delete();
    });

    test('add/read/delete', () async {
      var content = Uint8List.fromList([1, 2, 3, 4, 5]);
      var file = SyncedMediaFile.from(
        filename: 'test.webp',
        type: 'image/webp',
      );
      var ref = file.ref;

      await source.addMediaFile(bytes: content, file: file);
      expect(source.storagePath(ref), 'test_media/${file.path}');
      var storageFile = source.bucket.file(source.storagePath(ref));
      expect(await storageFile.exists(), isTrue);

      expect(await source.readMediaFileBytes(ref), content);

      await source.deleteMediaFile(ref);
      expect(await storageFile.exists(), isFalse);
      // No error
      await source.deleteMediaFile(ref);

      await expectLater(
        () => source.readMediaFileBytes(ref),
        throwsA(anything),
      );
    });

    test('download url', () async {
      var file = SyncedMediaFile.from(filename: 'test.webp');
      await source.addMediaFile(bytes: Uint8List(1), file: file);
      // storage_fs gives a file url
      var url = (await source.getMediaUrl(file.ref))!;
      expect(url.scheme, 'file');
      expect(url.path, endsWith(file.path));
    });

    test('public url', () async {
      var publicSource = SyncedMediaSourceStorage(
        storage: storage,
        rootPath: 'test_media',
        urlBuilder: syncedMediaStoragePublicUrlBuilder(),
      );
      var ref = SyncedMediaFileRef.fromPath('ab/cd/ef/abcdef_test.webp');
      expect(
        (await publicSource.getMediaUrl(ref)).toString(),
        'https://firebasestorage.googleapis.com/v0/b/test_bucket/o/'
        'test_media%2Fab%2Fcd%2Fef%2Fabcdef_test.webp?alt=media',
      );
      expect(
        syncedMediaStoragePublicUrlBuilder(
          endpoint: Uri.parse('http://localhost:9199'),
        )(StorageFileRef('b', 'a/b')).toString(),
        'http://localhost:9199/v0/b/b/o/a%2Fb?alt=media',
      );
    });

    test('redirect url', () async {
      var redirectSource = SyncedMediaSourceStorage(
        storage: storage,
        rootPath: 'test_media',
        urlBuilder: (fileRef) => Uri.parse(
          'https://my.app/media',
        ).replace(pathSegments: ['media', ...fileRef.path.split('/')]),
      );
      var ref = SyncedMediaFileRef.fromPath('ab/cd/ef/abcdef_test.webp');
      expect(
        (await redirectSource.getMediaUrl(ref)).toString(),
        'https://my.app/media/test_media/ab/cd/ef/abcdef_test.webp',
      );
    });
  });
}
