import 'package:tekaly_firestore_synced/src/synced_fs_change.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_document.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_meta.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_refs.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_source.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore/utils/auto_id_generator.dart';

/// Options of a [SyncedFsCollection].
class SyncedFsCollectionOptions {
  /// When true (default), each write appends its change log entry in the same
  /// transaction as the document itself.
  ///
  /// Set it to false when the change log is fed by a cloud function trigger
  /// only (see `SyncedFsCollectionTrigger`).
  final bool writeChangeLog;

  /// When true (default), the change log entries embed the document content so
  /// that a consumer can synchronize with a single read per change.
  ///
  /// Set it to false to keep the change log small, consumers then fetch the
  /// documents with `SyncedFsSource.getSnapshot`.
  final bool changeLogIncludesData;

  /// Options.
  const SyncedFsCollectionOptions({
    this.writeChangeLog = true,
    this.changeLogIncludesData = true,
  });
}

/// Meta information and change log update inside a transaction.
///
/// Firestore requires every read to happen before any write in a transaction,
/// so [txnInit] must be called before anything is written.
class _TxnInfo<T extends CvFirestoreDocument> {
  final CvFirestoreTransaction txn;
  final SyncedFsCollection<T> collection;
  late final SyncedFsMetaInfoRecord meta;
  late int lastChangeId;

  _TxnInfo(this.txn, this.collection);

  Future<void> txnInit() async {
    meta = await txn.refGet(collection.refs.metaInfoDocRef);
    lastChangeId = meta.lastChangeId.v ?? 0;
  }

  /// Allocate the next modification number.
  int txnAllocateChangeId() => ++lastChangeId;

  /// Append the change log entry for [changeId] if enabled.
  void txnAddChange({
    required int changeId,
    required String docId,
    required bool deleted,
    Model? data,
  }) {
    if (!collection.options.writeChangeLog) {
      return;
    }
    var change = CvSyncedFsChangeRecord()
      ..changeId.v = changeId
      ..docId.v = docId
      ..deleted.v = deleted
      ..origin.v = SyncedFsChangeOrigin.write;
    if (!deleted && collection.options.changeLogIncludesData) {
      change.data.v = data;
    }
    var map = change.toMap()..withServerTimestamp(change.timestamp);
    txn.refSetMap(collection.refs.changeDocRef(changeId), map);
  }

  void txnEnd() {
    if (meta.lastChangeId.v != lastChangeId) {
      meta.lastChangeId.v = lastChangeId;
      txn.refSet(collection.refs.metaInfoDocRef, meta, SetOptions(merge: true));
    }
  }
}

/// Synced collection helper.
///
/// Every write allocates a modification number (`synced.changeId`), stamps the
/// document with it and, unless disabled, appends the matching immutable entry
/// in the change log, all in the same transaction. Deletions are soft: the
/// document stays as a tombstone (`synced.deleted`) so that consumers can pick
/// the deletion up.
class SyncedFsCollection<T extends CvFirestoreDocument> {
  /// Firestore instance
  final Firestore firestore;

  /// Options
  final SyncedFsCollectionOptions options;

  /// Hide it to prevent direct access
  final CvCollectionReference<T> _collection;

  /// Collection, change log and meta references.
  late final SyncedFsCollectionRefs refs = SyncedFsCollectionRefs(
    path: _collection.path,
  );

  /// Read only view of the collection, what a consumer synchronizes from.
  late final SyncedFsFirestoreSource source = SyncedFsFirestoreSource.fromRefs(
    firestore: firestore,
    refs: refs,
  );

  /// Creates a [SyncedFsCollection] with [firestore] instance and target [_collection] reference.
  SyncedFsCollection({
    required this.firestore,
    required CvCollectionReference<T> collection,
    this.options = const SyncedFsCollectionOptions(),
    // ignore: prefer_initializing_formals
  }) : _collection = collection {
    cvInitSyncedFsBuilders();
  }

  /// The meta information, null if nothing was ever written.
  Future<SyncedFsMetaInfoRecord?> getMetaInfo() => source.getMetaInfo();

  /// The last modification number allocated in the collection, 0 if none.
  Future<int> getLastChangeId() async =>
      (await getMetaInfo())?.lastChangeId.v ?? 0;

  /// "Give me everything newer than modification number X".
  Future<SyncedFsChangeList> getChangeList({int? afterChangeId, int? limit}) =>
      source.getChangeList(afterChangeId: afterChangeId, limit: limit);

  /// "Give me a full snapshot of these document ids" (or of everything when
  /// [docIds] is null).
  Future<SyncedFsSnapshot> getSnapshot({List<String>? docIds}) =>
      source.getSnapshot(docIds: docIds);

  /// Get a document
  Future<T> getDoc(String id) async {
    var ref = _collection.doc(id);
    var map = (await ref.raw(firestore).get()).dataOrNull;
    var doc = ref.cv();
    if (map != null) {
      var synced = map.syncedInfoOrNull;
      var exists = synced?.deleted.v == false;

      if (!exists) {
        var docBase = doc as CvFirestoreDocumentBase;
        // ignore: deprecated_member_use
        docBase.exists = false;
      } else {
        doc.fromMap(map);
      }
    }
    return doc;
  }

  /// Get a document map if it exists
  Future<Model?> getMap(String id) async {
    var map = (await _collection.doc(id).raw(firestore).get()).dataOrNull;
    if (map != null) {
      var synced = map.syncedInfoOrNull;
      var exists = synced?.deleted.v == false;
      if (!exists) {
        return null;
      }
      return map;
    }
    return null;
  }

  void _mapUpdate(Model map, int lastChangeId, {bool deleted = false}) {
    map[syncedFieldKey] =
        (CvSyncedFsDocumentSyncedInfo()
              ..deleted.v = deleted
              ..changeId.v = lastChangeId)
            .toMapWithServerTimestamp();
  }

  Model _fullRecordModelFromMap(
    Model map,
    int lastChangeId, {
    bool deleted = false,
  }) {
    map = Model.of(map);
    _mapUpdate(map, lastChangeId, deleted: deleted);
    return map;
  }

  /// Delete a doc
  Future<void> deleteDoc(String id) async {
    return await firestore.cvRunTransaction((txn) async {
      var txnInfo = _TxnInfo<T>(txn, this);
      await txnInfo.txnInit();

      var ref = _collection.doc(id);
      var existingSnapshot = await txn.get(ref.raw(firestore));
      if (existingSnapshot.exists) {
        var lastChangeId = txnInfo.txnAllocateChangeId();
        var newMap = Model.of(existingSnapshot.data);
        _mapUpdate(newMap, lastChangeId, deleted: true);
        txn.refSetMap(ref, newMap);
        txnInfo.txnAddChange(changeId: lastChangeId, docId: id, deleted: true);

        txnInfo.txnEnd();
      }
    });
  }

  /// Add a document, returns its id
  Future<String> addDoc(T doc) {
    return addMap(doc.toMap());
  }

  /// Add a Map, returns its id
  Future<String> addMap(Model map) async {
    return await firestore.cvRunTransaction((txn) async {
      var txnInfo = _TxnInfo<T>(txn, this);
      await txnInfo.txnInit();

      var uniqueId = await _collection.raw(firestore).txnGenerateUniqueId(txn);

      var lastChangeId = txnInfo.txnAllocateChangeId();

      var ref = _collection.doc(uniqueId);
      txn.refSetMap(ref, _fullRecordModelFromMap(map, lastChangeId));
      txnInfo.txnAddChange(
        changeId: lastChangeId,
        docId: uniqueId,
        deleted: false,
        data: map,
      );

      txnInfo.txnEnd();
      return uniqueId;
    });
  }

  /// Set a Map
  Future<void> setMap(String id, Model map) async {
    return await firestore.cvRunTransaction((txn) async {
      var txnInfo = _TxnInfo<T>(txn, this);
      await txnInfo.txnInit();

      var lastChangeId = txnInfo.txnAllocateChangeId();

      var ref = _collection.doc(id);
      txn.refSetMap(ref, _fullRecordModelFromMap(map, lastChangeId));
      txnInfo.txnAddChange(
        changeId: lastChangeId,
        docId: id,
        deleted: false,
        data: map,
      );

      txnInfo.txnEnd();
    });
  }

  /// Set a document
  Future<void> setDoc(String id, T doc) {
    return setMap(id, doc.toMap());
  }

  @override
  String toString() => 'SyncedFsCollection(${refs.path})';
}
