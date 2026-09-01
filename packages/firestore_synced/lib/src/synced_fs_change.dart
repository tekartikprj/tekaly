import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

/// Change id (modification number) field key
const changeChangeIdFieldKey = 'changeId';

/// Document id field key
const changeDocIdFieldKey = 'docId';

/// Deleted field key
const changeDeletedFieldKey = 'deleted';

/// Timestamp field key (when the entry was appended)
const changeTimestampFieldKey = 'timestamp';

/// Document update time field key
const changeUpdateTimeFieldKey = 'updateTime';

/// Data field key
const changeDataFieldKey = 'data';

/// Origin field key
const changeOriginFieldKey = 'origin';

/// How a change log entry was produced.
class SyncedFsChangeOrigin {
  /// Written in the same transaction as the document (primary, in process).
  static const write = 'write';

  /// Written by a cloud function trigger (primary, out of process).
  static const trigger = 'trigger';

  /// Written by an on demand change log rebuild.
  static const rebuild = 'rebuild';

  /// Written by a scheduled reconciliation walking recent update times.
  static const reconcile = 'reconcile';
}

/// Width of the zero padded change log document id.
const syncedFsChangeDocIdWidth = 16;

/// Change log document id for [changeId].
///
/// Zero padded so that the natural document id order matches the change id
/// order, and so that appending the same change twice is idempotent.
String syncedFsChangeDocId(int changeId) =>
    changeId.toString().padLeft(syncedFsChangeDocIdWidth, '0');

/// Change id from a change log document id, null if not a valid entry id.
int? syncedFsChangeDocIdToChangeId(String docId) => int.tryParse(docId);

/// An immutable change log entry, in `<collection>_changes`.
///
/// One entry per document modification. The entry id is the zero padded
/// [changeId] so writing the same change twice is a no-op.
class CvSyncedFsChangeRecord extends CvFirestoreDocumentBase {
  /// The modification number of the document at that change.
  final changeId = CvField<int>(changeChangeIdFieldKey);

  /// The source document id in the tracked collection.
  final docId = CvField<String>(changeDocIdFieldKey);

  /// True when the document was deleted (tombstone).
  final deleted = CvField<bool>(changeDeletedFieldKey);

  /// When the entry was appended to the change log (server timestamp).
  final timestamp = CvField<Timestamp>(changeTimestampFieldKey);

  /// The source document update time, when known.
  final updateTime = CvField<Timestamp>(changeUpdateTimeFieldKey);

  /// The document content (without the `synced` information), null when
  /// deleted or when the change log is configured without data.
  ///
  /// Since this is 2 level deep, content is not indexed.
  final data = CvField<Model>(changeDataFieldKey);

  /// How the entry was produced, see [SyncedFsChangeOrigin].
  final origin = CvField<String>(changeOriginFieldKey);

  @override
  List<CvField> get fields => [
    changeId,
    docId,
    deleted,
    timestamp,
    updateTime,
    data,
    origin,
  ];
}

/// Change log helpers.
extension CvSyncedFsChangeRecordExt on CvSyncedFsChangeRecord {
  /// True when the entry only carries the deletion/modification information
  /// and the document content must be fetched separately.
  bool get needsSnapshot => deleted.v != true && data.v == null;
}

/// A list of change log entries, and the last change id reached.
class SyncedFsChangeList {
  /// The entries, ordered by change id.
  final List<CvSyncedFsChangeRecord> list;

  /// Last change id read, null when [list] is empty.
  final int? lastChangeId;

  /// Change list.
  SyncedFsChangeList(this.list, this.lastChangeId);

  /// True if empty.
  bool get isEmpty => list.isEmpty;

  /// True if not empty.
  bool get isNotEmpty => list.isNotEmpty;

  /// Item count.
  int get length => list.length;

  @override
  String toString() =>
      'SyncedFsChangeList(${list.length} item(s), lastChangeId: $lastChangeId)';
}
