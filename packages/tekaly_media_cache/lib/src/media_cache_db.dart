import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:sembast/timestamp.dart';

import 'tekaly_media_cache.dart';

class DbMedia extends DbStringRecordBase {
  final name = CvField<String>('name');
  final type = CvField<String>('type');
  final size = CvField<int>('size');
  final cached = CvField<Timestamp>('timestamp');

  String get nameValue => name.value ?? 'media_default';
  @override
  CvFields get fields => [name, type, size, cached];
}

extension DbMediaExt on DbMedia {
  TekalyMediaInfo get mediaInfo {
    return TekalyMediaInfo(
      name: nameValue,
      type: type.value,
      size: size.value ?? 0,
    );
  }
}

final dbMediaStore = cvStringStoreFactory.store<DbMedia>('media');

class MediaCacheDb {}
