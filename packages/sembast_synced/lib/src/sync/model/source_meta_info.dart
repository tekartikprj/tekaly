import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

/// Last change id (or change num)
const metaLastChangeIdKey = 'lastChangeId';

/// meta version key
const metaVersionIdKey = 'version';

/// Min increment change id key
const metaMinIncrementalChangeIdKey = 'minIncrementalChangeId';

/// Compat
typedef CvMetaInfoRecord = CvMetaInfo;

/// /meta/info
abstract class CvMetaInfo implements CvModel {
  /// Factory constructor
  factory CvMetaInfo() => _CvMetaInfoRecord();

  /// Min incremental change id
  CvField<int> get minIncrementalChangeId;

  /// Last incremental change id
  CvField<int> get lastChangeId;

  /// Version, simply increment it to force a full sync
  ///
  /// Set to 1 upon read if not set yet
  CvField<int> get version;
}

class _CvMetaInfoRecord extends CvModelBase with CvMetaInfoMixin {}

/// Record mixin
mixin CvMetaInfoMixin implements CvMetaInfo {
  /// Min incremental change id
  @override
  final minIncrementalChangeId = CvField<int>(metaMinIncrementalChangeIdKey);

  /// Last incremental change id
  @override
  final lastChangeId = CvField<int>(metaLastChangeIdKey);

  /// Version, simply increment it to force a full sync
  ///
  /// Set to 1 upon read if not set yet
  @override
  final version = CvField<int>(metaVersionIdKey);

  @override
  List<CvField> get fields => [minIncrementalChangeId, lastChangeId, version];
}

/// /meta/info
