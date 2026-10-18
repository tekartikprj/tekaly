import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:tekartik_firebase_storage/storage.dart';
import 'package:tekartik_firebase_storage/utils/link.dart';

import 'synced_media_file.dart';
import 'synced_media_source.dart';

/// Builds the network url of a media content stored at [fileRef].
typedef SyncedMediaStorageUrlBuilder =
    FutureOr<Uri?> Function(StorageFileRef fileRef);

/// Cache control of a media content: it never changes once written (a new
/// media gets a new path).
const syncedMediaStorageCacheControlImmutable = 'max-age=31536000, immutable';

/// Url builder of the Firebase Storage download api
/// (`<endpoint>/v0/b/<bucket>/o/<path>?alt=media`), computed without any
/// network call.
///
/// The url is permanent but only works if the Storage rules let read the file
/// without authentication (a plain `Image.network` or html `img` sends no
/// credentials).
SyncedMediaStorageUrlBuilder syncedMediaStoragePublicUrlBuilder({
  Uri? endpoint,
}) {
  var base = endpoint ?? Uri.parse('https://firebasestorage.googleapis.com');
  return (fileRef) => base.replace(
    pathSegments: [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      'v0',
      'b',
      fileRef.bucket,
      'o',
      fileRef.path,
    ],
    queryParameters: {'alt': 'media'},
  );
}

/// Media source in a Firebase Storage bucket, the contents in
/// `<rootPath>/<media path>`.
class SyncedMediaSourceStorage with SyncedMediaSourceMixin {
  /// Storage.
  final FirebaseStorage storage;

  /// Bucket name, the app default bucket if null.
  final String? bucketName;

  /// Root folder of the contents.
  final String rootPath;

  /// Cache control of the uploaded contents, for example
  /// [syncedMediaStorageCacheControlImmutable].
  final String? cacheControl;

  /// Network url builder, see [getMediaUrl].
  final SyncedMediaStorageUrlBuilder? urlBuilder;

  /// Media source in [rootPath] of [bucketName].
  SyncedMediaSourceStorage({
    required this.storage,
    this.bucketName,
    required this.rootPath,
    this.cacheControl,
    this.urlBuilder,
  });

  /// The bucket.
  Bucket get bucket => storage.bucket(bucketName);

  /// The actual bucket name.
  String get actualBucketName =>
      bucketName ?? storage.app.options.storageBucket ?? bucket.name;

  /// Path of [ref] in the bucket, [ref] must be valid (see
  /// [syncedMediaIsValidPath]).
  String storagePath(SyncedMediaFileRef ref) {
    if (!syncedMediaIsValidPath(ref.path)) {
      throw ArgumentError.value(ref.path, 'ref', 'invalid media path');
    }
    return url.join(rootPath, ref.path);
  }

  /// Storage reference of [ref].
  StorageFileRef storageFileRef(SyncedMediaFileRef ref) =>
      StorageFileRef(actualBucketName, storagePath(ref));

  @override
  Future<void> addMediaFile({
    required Uint8List bytes,
    required SyncedMediaFile file,
  }) async {
    await bucket
        .file(storagePath(file.ref))
        .upload(
          bytes,
          options: StorageUploadFileOptions(
            contentType: file.type,
            cacheControl: cacheControl,
          ),
        );
  }

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) async {
    try {
      await bucket.file(storagePath(ref)).delete();
    } catch (_) {
      // Ignore if file does not exist
    }
  }

  @override
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref) async {
    return await bucket.file(storagePath(ref)).readAsBytes();
  }

  /// The [urlBuilder] url if set, otherwise the storage download url:
  /// * Flutter (client sdk): a long lived url holding a download token
  ///   (`...?alt=media&token=...`), it works without authentication until the
  ///   token is revoked in the console; getting it needs read access.
  /// * rest: the download api url ([syncedMediaStoragePublicUrlBuilder]),
  ///   readable without authentication only if the rules allow it.
  /// * memory/io (storage_fs): a `file://` url.
  /// * admin sdk: none (null).
  @override
  Future<Uri?> getMediaUrl(SyncedMediaFileRef ref) async {
    var fileRef = storageFileRef(ref);
    var builder = urlBuilder;
    if (builder != null) {
      return await builder(fileRef);
    }
    try {
      var downloadUrl = await storage
          .ref(fileRef.toLink().toString())
          .getDownloadUrl();
      return Uri.parse(downloadUrl);
    } catch (e) {
      if (e is UnimplementedError || e is UnsupportedError) {
        return null;
      }
      rethrow;
    }
  }

  @override
  String toString() => 'SyncedMediaSourceStorage($actualBucketName/$rootPath)';
}
