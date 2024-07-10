import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

const metaLastChangeIdKey = 'lastChangeId';
const metaVersionIdKey = 'version';
const metaMinIncrementalChangeIdKey = 'minIncrementalChangeId';

/// /meta/info
class CvMetaInfoRecord extends CvModelBase {
  /// Min increment
  // final minIncrementalTimestamp = CvField<Timestamp>('minIncrementalTimestamp');

  /// Min incremental change id
  final minIncrementalChangeId = CvField<int>(metaMinIncrementalChangeIdKey);

  /// Last incremental change id
  final lastChangeId = CvField<int>(metaLastChangeIdKey);

  /// Version, simply increment it to force a full sync
  ///
  /// Set to 1 upon read if not set yet
  final version = CvField<int>(metaVersionIdKey);

  @override
  List<CvField> get fields => [minIncrementalChangeId, lastChangeId, version];
}
