import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// Change num field key, a.k.a the document modification number.
const syncedChangeIdFieldKey = 'changeId';

/// Deleted field key
const syncedDeletedFieldKey = 'deleted';

/// Dirty field key
const syncedDirtyFieldKey = 'dirty';

/// Timestamp field key (server update time), from [WithServerTimestampMixin]
const syncedTimestampFieldKey = 'timestamp';

/// Synced top field key
const syncedFieldKey = 'synced';

/// `synced.changeId` field path, usable in queries (order by/where)
const syncedChangeIdFieldPath = '$syncedFieldKey.$syncedChangeIdFieldKey';

/// `synced.deleted` field path, usable in queries (order by/where)
const syncedDeletedFieldPath = '$syncedFieldKey.$syncedDeletedFieldKey';

/// `synced.timestamp` field path, usable in queries (order by/where)
const syncedTimestampFieldPath = '$syncedFieldKey.$syncedTimestampFieldKey';

/// Synced info (typically in a "synced" field)
class CvSyncedFsDocumentSyncedInfo extends CvModelBase
    with WithServerTimestampMixin {
  /// Local key
  final deleted = CvField<bool>(syncedDeletedFieldKey);

  /// Last source change num.
  ///
  /// This is the document modification number: a strictly increasing number,
  /// unique in the collection, allocated on each write.
  final changeId = CvField<int>(syncedChangeIdFieldKey);

  /// Alias for [changeId], the document modification number.
  int? get modificationNumber => changeId.v;

  @override
  List<CvField> get fields => [...timedMixinFields, deleted, changeId];
}

/// Synced info helpers on a raw document map.
extension CvSyncedFsDocumentMapExt on Model {
  /// Read the `synced` sub map information, null if absent (i.e. the document
  /// was written without going through the synced helpers).
  CvSyncedFsDocumentSyncedInfo? get syncedInfoOrNull {
    var synced = this[syncedFieldKey];
    if (synced is Map) {
      return asModel(synced).cv<CvSyncedFsDocumentSyncedInfo>();
    }
    return null;
  }

  /// The document modification number, null if the document was never stamped.
  int? get syncedChangeIdOrNull => syncedInfoOrNull?.changeId.v;

  /// True if the document is a tombstone (soft deleted).
  bool get syncedIsDeleted => syncedInfoOrNull?.deleted.v == true;

  /// The document content without the `synced` information.
  Model get withoutSyncedInfo => Model.of(this)..remove(syncedFieldKey);
}
