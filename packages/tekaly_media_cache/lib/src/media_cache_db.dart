import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

import 'media_cache.dart';

/// The media model
class DbMedia extends DbStringRecordBase {
  /// name (local)
  final name = CvField<String>('name');

  /// type
  final type = CvField<String>('type');

  /// size
  final size = CvField<int>('size');

  /// timestamp
  final cached = CvField<Timestamp>('timestamp');

  /// name value not null
  String get nameValue => name.value ?? 'media_default';
  @override
  CvFields get fields => [name, type, size, cached];
}

/// Media info record extension
extension DbMediaExt on DbMedia {
  /// Convert to media info
  TekalyMediaInfo mediaInfo({required TekalyMediaKey key}) {
    return TekalyMediaInfo(
      key: key,

      name: nameValue,
      type: type.value,
      size: size.value ?? 0,
    );
  }
}

/// The store
final dbMediaStore = cvStringStoreFactory.store<DbMedia>('media');

/// One instance of the media model
final dbMediaModel = DbMedia();

/// The database
class MediaCacheDb {}
