import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// Last change num
const metaLastChangeIdKey = 'lastChangeId';

/// Version
const metaVersionIdKey = 'version';

/// Min incremental change id
const metaMinIncrementalChangeIdKey = 'minIncrementalChangeId';

/// /xxxx_meta/synced
class SyncedFsMetaInfoRecord extends CvFirestoreDocumentBase {
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
