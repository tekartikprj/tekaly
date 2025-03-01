import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// Change num field key
const syncedChangeIdFieldKey = 'changeId';

/// Deleted field key
const syncedDeletedFieldKey = 'deleted';

/// Dirty field key
const syncedDirtyFieldKey = 'dirty';

/// Synced top field key
const syncedFieldKey = 'synced';

/// Synced info (typically in a "synced" field)
class CvSyncedFsDocumentSyncedInfo extends CvModelBase
    with WithServerTimestampMixin {
  /// Local key
  final deleted = CvField<bool>(syncedDeletedFieldKey);

  /// Last source change num
  final changeId = CvField<int>(syncedChangeIdFieldKey);

  @override
  List<CvField> get fields => [...timedMixinFields, deleted, changeId];
}
