import 'dart:typed_data';

import 'synced_media_file.dart';

/// Remote source of the media contents.
abstract class SyncedMediaSource {
  /// Adds the content of a media file to the source.
  Future<void> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  });

  /// Reads the content of [ref].
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref);

  /// Deletes the content of [ref], no error if it does not exist.
  Future<void> deleteMediaFile(SyncedMediaFileRef ref);

  /// A network url reading the content of [ref] directly (an `Image.network`,
  /// an html `img`, a player), null if the source has none.
  Future<Uri?> getMediaUrl(SyncedMediaFileRef ref);
}

/// Default [SyncedMediaSource] implementations, no network url.
mixin SyncedMediaSourceMixin implements SyncedMediaSource {
  @override
  Future<Uri?> getMediaUrl(SyncedMediaFileRef ref) async => null;
}

/// In memory source, for tests.
class SyncedMediaSourceMemory with SyncedMediaSourceMixin {
  final _contents = <String, Uint8List>{};

  /// Content paths in the source.
  Iterable<String> get paths => _contents.keys;

  @override
  Future<void> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  }) async {
    _contents[file.path] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) async {
    _contents.remove(ref.path);
  }

  @override
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref) async {
    var bytes = _contents[ref.path];
    if (bytes == null) {
      throw StateError('Media content $ref not found');
    }
    return Uint8List.fromList(bytes);
  }
}

/// Source reading from [readSource] (contents and urls) and writing to
/// [writeSource], for example reading directly from the bucket (public or
/// download urls) and writing through an api (`SyncedMediaSourceApi`).
class SyncedMediaSourceHybrid implements SyncedMediaSource {
  /// Read source (contents and urls).
  final SyncedMediaSource readSource;

  /// Write source (add and delete).
  final SyncedMediaSource writeSource;

  /// Source reading from [readSource] and writing to [writeSource].
  SyncedMediaSourceHybrid({
    required this.readSource,
    required this.writeSource,
  });

  @override
  Future<void> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  }) => writeSource.addMediaFile(file: file, bytes: bytes);

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) =>
      writeSource.deleteMediaFile(ref);

  @override
  Future<Uri?> getMediaUrl(SyncedMediaFileRef ref) =>
      readSource.getMediaUrl(ref);

  @override
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref) =>
      readSource.readMediaFileBytes(ref);

  @override
  String toString() =>
      'SyncedMediaSourceHybrid(read: $readSource, write: $writeSource)';
}
