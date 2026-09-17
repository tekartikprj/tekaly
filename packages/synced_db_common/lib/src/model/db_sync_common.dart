import 'package:cv/cv.dart';

import '../synced_db_common_types.dart';

/// Sync timestamp key.
const syncTimestampKey = 'syncTimestamp';

/// Sync change id key.
const syncChangeIdKey = 'syncChangeId';

/// Record store field key.
const recordStoreFieldKey = 'store';

/// Record key field key.
const recordKeyFieldKey = 'key';

/// Record deleted field key.
const recordDeletedFieldKey = 'deleted';

/// Record value field key.
const recordValueFieldKey = 'value';

/// Record dirty field key.
const recordDirtyFieldKey = 'dirty';

/// Record field key.
const recordFieldKey = 'record';

/// Sync id key.
const syncIdKey = 'syncId';

/// Local sync record, common to the sembast and sdb implementations.
abstract class DbSyncRecordCommon implements CvModel {
  /// Local store
  CvField<String> get store;

  /// Local key
  CvField<String> get key;

  /// Whether the record is deleted
  bool get isDeleted;

  /// Local dirty/deleted/added
  /// Whether the record is dirty
  bool get isDirty;

  /// Source id
  CvField<String> get syncId;

  /// Source timestamp
  CvField<SyncedDbTimestamp> get syncTimestamp;

  /// Source change id
  CvField<int> get syncChangeId;
}

/// Local sync meta info, common to the sembast and sdb implementations.
abstract class DbSyncMetaInfoCommon implements CvModel {
  /// source
  CvField<String> get source;

  /// sourceVersion
  CvField<int> get sourceVersion;

  /// Source id if any TODO
  CvField<String> get sourceId;

  /// Last timestamp
  CvField<SyncedDbTimestamp> get lastTimestamp;

  /// Last change id, 0 if none after first sync
  CvField<int> get lastChangeId;
}
