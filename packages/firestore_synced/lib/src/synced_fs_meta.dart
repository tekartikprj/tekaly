import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// Last change num
const metaLastChangeIdKey = 'lastChangeId';

/// Version
const metaVersionIdKey = 'version';

/// Min incremental change id
const metaMinIncrementalChangeIdKey = 'minIncrementalChangeId';

/// Last change id present in the change log
const metaChangeLogChangeIdKey = 'changeLogChangeId';

/// Last reconciliation timestamp
const metaLastReconcileTimestampKey = 'lastReconcileTimestamp';

/// /xxxx_meta/info
class SyncedFsMetaInfoRecord extends CvFirestoreDocumentBase {
  /// Min increment
  // final minIncrementalTimestamp = CvField<Timestamp>('minIncrementalTimestamp');

  /// Min incremental change id
  ///
  /// A client which last synchronized before this change id must do a full
  /// resynchronization (the change log has been truncated below it).
  final minIncrementalChangeId = CvField<int>(metaMinIncrementalChangeIdKey);

  /// Last incremental change id, a.k.a the last modification number allocated
  /// in the collection.
  final lastChangeId = CvField<int>(metaLastChangeIdKey);

  /// Version, simply increment it to force a full sync
  ///
  /// Set to 1 upon read if not set yet
  final version = CvField<int>(metaVersionIdKey);

  /// Last change id known to be present in the change log.
  ///
  /// Written by the change log rebuilder, it is the resume point of the next
  /// rebuild. It can lag behind [lastChangeId] when the primary (trigger) path
  /// failed.
  final changeLogChangeId = CvField<int>(metaChangeLogChangeIdKey);

  /// Last time a reconciliation (cron) walked the collection.
  final lastReconcileTimestamp = CvField<Timestamp>(
    metaLastReconcileTimestampKey,
  );

  @override
  List<CvField> get fields => [
    minIncrementalChangeId,
    lastChangeId,
    version,
    changeLogChangeId,
    lastReconcileTimestamp,
  ];
}
