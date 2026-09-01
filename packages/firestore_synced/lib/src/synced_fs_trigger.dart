import 'package:collection/collection.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_change.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_document.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_refs.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

const _deepEquality = DeepCollectionEquality();

/// Appends entries to the immutable change log, allocating modification
/// numbers when a document was written without one.
///
/// Every operation is idempotent: appending the same change id twice writes
/// the same document, so a cloud function retried at least once (the firestore
/// trigger delivery guarantee) never duplicates an entry.
class SyncedFsChangeWriter {
  /// Firestore instance, usually the admin one on the server side.
  final Firestore firestore;

  /// Collection, change log and meta references.
  final SyncedFsCollectionRefs refs;

  /// When true (default), the change log entries embed the document content.
  final bool includeData;

  /// Change writer on the collection at [path].
  SyncedFsChangeWriter({
    required this.firestore,
    required String path,
    this.includeData = true,
  }) : refs = SyncedFsCollectionRefs(path: path);

  /// Change writer on existing [refs].
  SyncedFsChangeWriter.fromRefs({
    required this.firestore,
    required this.refs,
    this.includeData = true,
  }) {
    cvInitSyncedFsBuilders();
  }

  /// Append the change log entry for an already stamped document.
  ///
  /// Returns the appended entry, or null when it was already there.
  Future<CvSyncedFsChangeRecord?> appendChange({
    required int changeId,
    required String docId,
    required bool deleted,
    Model? data,
    Timestamp? updateTime,
    String origin = SyncedFsChangeOrigin.trigger,
  }) async {
    var changeRef = refs.changeDocRef(changeId);
    return await firestore.cvRunTransaction((txn) async {
      var existing = await txn.refGet(changeRef);
      if (existing.exists) {
        return null;
      }
      return _txnSetChange(
        txn,
        changeId: changeId,
        docId: docId,
        deleted: deleted,
        data: data,
        updateTime: updateTime,
        origin: origin,
      );
    });
  }

  /// Allocate a modification number for [docId], stamp the document with it
  /// and append the matching change log entry.
  ///
  /// Used to heal documents written without going through
  /// [SyncedFsCollection], by the trigger or by the change log rebuilder.
  /// Returns null when there was nothing to do (the document was already
  /// stamped and its entry already present).
  ///
  /// Set [force] to allocate a new modification number even when the document
  /// already has one, for a content changed behind the helpers' back.
  Future<CvSyncedFsChangeRecord?> stampAndAppendChange({
    required String docId,
    String origin = SyncedFsChangeOrigin.trigger,
    bool force = false,
  }) async {
    var docRef = refs.collection.doc(docId);
    return await firestore.cvRunTransaction((txn) async {
      var meta = await txn.refGet(refs.metaInfoDocRef);
      var snapshot = await txn.get(docRef.raw(firestore));
      var map = snapshot.exists ? snapshot.data : null;
      var deleted = map == null || map.syncedIsDeleted;
      var changeId = map?.syncedChangeIdOrNull;

      if (changeId != null && !force) {
        /// Already stamped, only the change log entry may be missing.
        var existing = await txn.refGet(refs.changeDocRef(changeId));
        if (existing.exists) {
          return null;
        }
        return _txnSetChange(
          txn,
          changeId: changeId,
          docId: docId,
          deleted: deleted,
          data: map,
          updateTime: snapshot.updateTime,
          origin: origin,
        );
      }

      var newChangeId = (meta.lastChangeId.v ?? 0) + 1;
      if (map != null) {
        var newMap = Model.of(map)
          ..[syncedFieldKey] =
              (CvSyncedFsDocumentSyncedInfo()
                    ..deleted.v = deleted
                    ..changeId.v = newChangeId)
                  .toMapWithServerTimestamp();
        txn.refSetMap(docRef, newMap);
      }
      meta.lastChangeId.v = newChangeId;
      txn.refSet(refs.metaInfoDocRef, meta, SetOptions(merge: true));
      return _txnSetChange(
        txn,
        changeId: newChangeId,
        docId: docId,
        deleted: deleted,
        data: map,
        updateTime: snapshot.updateTime,
        origin: origin,
      );
    });
  }

  CvSyncedFsChangeRecord _txnSetChange(
    CvFirestoreTransaction txn, {
    required int changeId,
    required String docId,
    required bool deleted,
    required Model? data,
    required Timestamp? updateTime,
    required String origin,
  }) {
    var changeRef = refs.changeDocRef(changeId);
    var change = CvSyncedFsChangeRecord()
      ..changeId.v = changeId
      ..docId.v = docId
      ..deleted.v = deleted
      ..origin.v = origin;
    if (updateTime != null) {
      change.updateTime.v = updateTime;
    }
    if (!deleted && includeData && data != null) {
      change.data.v = data.withoutSyncedInfo;
    }
    txn.refSetMap(
      changeRef,
      change.toMap()..withServerTimestamp(change.timestamp),
    );
    return change..path = changeRef.path;
  }
}

/// Cloud function trigger helper.
///
/// Wire it on a document write trigger of the tracked collection so that the
/// change log is fed even for writes that do not go through
/// [SyncedFsCollection] (client SDK writes, admin scripts, imports).
///
/// ```dart
/// var trigger = SyncedFsCollectionTrigger(firestore: firestore, path: 'item');
/// // in the onWrite cloud function of `item/{docId}`
/// await trigger.onDocumentWrite(docId: docId, before: before, after: after);
/// ```
class SyncedFsCollectionTrigger {
  /// The change log writer.
  final SyncedFsChangeWriter writer;

  /// Collection, change log and meta references.
  SyncedFsCollectionRefs get refs => writer.refs;

  /// Trigger on the collection at [path].
  SyncedFsCollectionTrigger({
    required Firestore firestore,
    required String path,
    bool includeData = true,
  }) : writer = SyncedFsChangeWriter(
         firestore: firestore,
         path: path,
         includeData: includeData,
       );

  /// Trigger on an existing [writer].
  SyncedFsCollectionTrigger.fromWriter(this.writer);

  /// Handle a document write.
  ///
  /// [before] and [after] are the raw document maps, null when the document
  /// did not exist (creation) or does not exist any more (hard deletion).
  ///
  /// Returns the appended change log entry, or null when there was nothing to
  /// do (already tracked, or no actual content change).
  Future<CvSyncedFsChangeRecord?> onDocumentWrite({
    required String docId,
    Model? before,
    Model? after,
    Timestamp? updateTime,
    String origin = SyncedFsChangeOrigin.trigger,
  }) async {
    if (after == null) {
      /// Hard deletion, nothing left to stamp: allocate a change id for the
      /// tombstone entry.
      return await writer.stampAndAppendChange(docId: docId, origin: origin);
    }
    var changeId = after.syncedChangeIdOrNull;
    if (changeId == null) {
      /// Written without the synced helpers, heal it.
      return await writer.stampAndAppendChange(docId: docId, origin: origin);
    }
    if (before != null && before.syncedChangeIdOrNull == changeId) {
      /// The modification number did not move.
      if (_deepEquality.equals(
        before.withoutSyncedInfo,
        after.withoutSyncedInfo,
      )) {
        /// Nothing changed (or only the synced timestamp), the entry for this
        /// change id is already there.
        return null;
      }

      /// Content changed without a new modification number, heal it.
      return await writer.stampAndAppendChange(
        docId: docId,
        origin: origin,
        force: true,
      );
    }
    return await writer.appendChange(
      changeId: changeId,
      docId: docId,
      deleted: after.syncedIsDeleted,
      data: after,
      updateTime: updateTime,
      origin: origin,
    );
  }

  /// Handle a document write from snapshots.
  Future<CvSyncedFsChangeRecord?> onDocumentSnapshotWrite({
    DocumentSnapshot? before,
    DocumentSnapshot? after,
    String? docId,
  }) async {
    docId ??= (after ?? before)?.ref.id;
    if (docId == null) {
      throw ArgumentError.notNull('docId');
    }
    return await onDocumentWrite(
      docId: docId,
      before: (before?.exists ?? false) ? before!.data : null,
      after: (after?.exists ?? false) ? after!.data : null,
      updateTime: after?.updateTime,
    );
  }

  @override
  String toString() => 'SyncedFsCollectionTrigger(${refs.path})';
}
