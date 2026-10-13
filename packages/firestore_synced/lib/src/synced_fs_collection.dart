import 'dart:async';

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
  /// only (see `SyncedFsCollectionTrigger`). Ignored when [collectionChanges]
  /// is true (no change log at all).
  final bool writeChangeLog;

  /// When true (default), the change log entries embed the document content so
  /// that a consumer can synchronize with a single read per change.
  ///
  /// Set it to false to keep the change log small, consumers then fetch the
  /// documents with `SyncedFsSource.getSnapshot`.
  final bool changeLogIncludesData;

  /// When true, no change log is written (2 writes per change: the document
  /// and the meta) and the changes are read from the collection itself,
  /// ordered by `synced.changeId` (tombstones included), see
  /// [SyncedFsFirestoreSource.collectionChanges].
  ///
  /// Only valid when every write goes through the helper (or the trigger):
  /// the collection then holds the current modification number of each
  /// document, which is all a consumer asking for "everything newer than X"
  /// needs. A single field index on `synced.changeId` is enough.
  final bool collectionChanges;

  /// When false (default), a tombstone only keeps the `synced` information:
  /// the document content is dropped on deletion. When true, the content of
  /// the deleted document is kept next to it.
  final bool tombstoneKeepsData;

  /// Options.
  const SyncedFsCollectionOptions({
    this.writeChangeLog = true,
    this.changeLogIncludesData = true,
    this.collectionChanges = false,
    this.tombstoneKeepsData = false,
  });

  /// True when the writes append to the change log.
  bool get writesChangeLog => writeChangeLog && !collectionChanges;
}

/// A document read in a [SyncedFsTransaction].
class SyncedFsTransactionDoc<T extends CvFirestoreDocument> {
  /// The document, without its `synced` information; `exists` is false when
  /// the document does not exist in firestore (a tombstone exists).
  final T doc;

  /// The `synced` information, null when the document does not exist or was
  /// written around the synced helpers.
  final CvSyncedFsDocumentSyncedInfo? syncedInfo;

  /// A document read in a transaction.
  SyncedFsTransactionDoc({required this.doc, required this.syncedInfo});

  /// True when the document exists in firestore (a tombstone included).
  bool get exists => doc.exists;

  /// True for a tombstone (soft deleted).
  bool get isDeleted => syncedInfo?.deleted.v == true;

  /// True when the document exists and is not a tombstone.
  bool get isAlive => exists && !isDeleted;

  /// Its modification number, null if never stamped.
  int? get changeId => syncedInfo?.changeId.v;

  @override
  String toString() =>
      'SyncedFsTransactionDoc(${doc.path}, '
      '${isAlive ? 'alive' : (isDeleted ? 'deleted' : 'missing')}, '
      'changeId: $changeId)';
}

/// A transaction on a [SyncedFsCollection], see
/// [SyncedFsCollection.runTransaction].
///
/// Firestore requires every read to happen before any write in a
/// transaction: [getDoc] (and reads of other documents through
/// [transaction]) must come before [setDoc] and [deleteDoc]. Each write
/// allocates the next modification number from [meta], stamps the document
/// and, unless the collection is configured otherwise, appends its change
/// log entry. The meta is written once, when the action completes, only
/// when something was allocated.
class SyncedFsTransaction<T extends CvFirestoreDocument> {
  /// The collection.
  final SyncedFsCollection<T> collection;

  /// The underlying transaction, to read and write other documents.
  final CvFirestoreTransaction transaction;

  /// The meta information, read when the transaction starts.
  late final SyncedFsMetaInfoRecord meta;

  late int _lastChangeId;
  late final int _initialChangeId;
  var _written = false;
  final _readMaps = <String, Model?>{};

  SyncedFsTransaction._(this.collection, this.transaction);

  Firestore get _firestore => collection.firestore;

  SyncedFsCollectionOptions get _options => collection.options;

  /// The last modification number allocated so far (the one of the meta
  /// when nothing was written yet).
  int get lastChangeId => _lastChangeId;

  Future<void> _init() async {
    meta = await transaction.refGet(collection.refs.metaInfoDocRef);
    _lastChangeId = _initialChangeId = meta.lastChangeId.v ?? 0;
  }

  void _checkCanRead() {
    if (_written) {
      throw StateError('read after a write in ${collection.refs.path}');
    }
  }

  /// Read the document [id] (before any write).
  Future<SyncedFsTransactionDoc<T>> getDoc(String id) async {
    _checkCanRead();
    var ref = collection._collection.doc(id);
    var snapshot = await transaction.get(ref.raw(_firestore));
    var map = snapshot.exists ? snapshot.data : null;
    _readMaps[id] = map;
    var doc = snapshot.cv<T>();
    if (doc is Map) {
      // A map document holds every key: strip the bookkeeping.
      (doc as Map).remove(syncedFieldKey);
    }
    return SyncedFsTransactionDoc(doc: doc, syncedInfo: map?.syncedInfoOrNull);
  }

  /// A new unique document id in the collection (a read: before any write).
  Future<String> newDocId() async {
    _checkCanRead();
    return await collection._collection
        .raw(_firestore)
        .txnGenerateUniqueId(transaction);
  }

  int _allocate() {
    _written = true;
    return ++_lastChangeId;
  }

  /// Write [doc] as the document [id], returns its modification number.
  int setDoc(String id, T doc) => setMap(id, doc.toMap());

  /// Write [map] as the document [id], returns its modification number.
  int setMap(String id, Model map) {
    var changeId = _allocate();
    var ref = collection._collection.doc(id);
    var content = Model.of(map)..remove(syncedFieldKey);
    transaction.refSetMap(
      ref,
      Model.of(content)..[syncedFieldKey] = _syncedMap(changeId),
    );
    _addChange(changeId: changeId, docId: id, deleted: false, data: content);
    return changeId;
  }

  /// Soft delete the document [id]: a tombstone, returns its modification
  /// number.
  ///
  /// The tombstone only holds the `synced` information, unless the
  /// collection keeps the data of tombstones
  /// ([SyncedFsCollectionOptions.tombstoneKeepsData]) and the document was
  /// read in this transaction ([getDoc]).
  int deleteDoc(String id) {
    var changeId = _allocate();
    var ref = collection._collection.doc(id);
    var content = _options.tombstoneKeepsData
        ? (_readMaps[id]?.withoutSyncedInfo ?? <String, Object?>{})
        : <String, Object?>{};
    transaction.refSetMap(
      ref,
      Model.of(content)..[syncedFieldKey] = _syncedMap(changeId, deleted: true),
    );
    _addChange(changeId: changeId, docId: id, deleted: true);
    return changeId;
  }

  Model _syncedMap(int changeId, {bool deleted = false}) =>
      (CvSyncedFsDocumentSyncedInfo()
            ..deleted.v = deleted
            ..changeId.v = changeId)
          .toMapWithServerTimestamp();

  void _addChange({
    required int changeId,
    required String docId,
    required bool deleted,
    Model? data,
  }) {
    if (!_options.writesChangeLog) {
      return;
    }
    var change = CvSyncedFsChangeRecord()
      ..changeId.v = changeId
      ..docId.v = docId
      ..deleted.v = deleted
      ..origin.v = SyncedFsChangeOrigin.write;
    if (!deleted && _options.changeLogIncludesData) {
      change.data.v = data;
    }
    var map = change.toMap()..withServerTimestamp(change.timestamp);
    transaction.refSetMap(collection.refs.changeDocRef(changeId), map);
  }

  void _end() {
    if (_lastChangeId != _initialChangeId) {
      meta.lastChangeId.v = _lastChangeId;
      transaction.refSet(
        collection.refs.metaInfoDocRef,
        meta,
        SetOptions(merge: true),
      );
    }
  }
}

/// Synced collection helper.
///
/// Every write allocates a modification number (`synced.changeId`), stamps the
/// document with it and, unless disabled, appends the matching immutable entry
/// in the change log, all in the same transaction. Deletions are soft: the
/// document stays as a tombstone (`synced.deleted`, content dropped unless
/// [SyncedFsCollectionOptions.tombstoneKeepsData]) so that consumers can pick
/// the deletion up.
///
/// [runTransaction] combines reads, application logic and several writes in
/// one transaction.
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

  /// Read only view of the collection, what a consumer synchronizes from
  /// (its changes read from the collection itself when
  /// [SyncedFsCollectionOptions.collectionChanges]).
  late final SyncedFsFirestoreSource source = SyncedFsFirestoreSource.fromRefs(
    firestore: firestore,
    refs: refs,
    collectionChanges: options.collectionChanges,
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

  /// Run [action] in a transaction of the collection: read documents
  /// ([SyncedFsTransaction.getDoc], other ones through
  /// [SyncedFsTransaction.transaction]), then write them, each write
  /// allocating its modification number, the meta written once at the end.
  ///
  /// The action may run more than once (firestore retries a transaction on
  /// contention, the meta being read by every write, concurrent writes do
  /// contend).
  Future<R> runTransaction<R>(
    FutureOr<R> Function(SyncedFsTransaction<T> txn) action,
  ) {
    return firestore.cvRunTransaction((transaction) async {
      var txn = SyncedFsTransaction<T>._(this, transaction);
      await txn._init();
      var result = await action(txn);
      txn._end();
      return result;
    });
  }

  /// Delete a doc: a tombstone (see [SyncedFsTransaction.deleteDoc]), only
  /// if it exists and is not deleted already.
  Future<void> deleteDoc(String id) async {
    await runTransaction((txn) async {
      var existing = await txn.getDoc(id);
      if (existing.isAlive) {
        txn.deleteDoc(id);
      }
    });
  }

  /// Add a document, returns its id
  Future<String> addDoc(T doc) {
    return addMap(doc.toMap());
  }

  /// Add a Map, returns its id
  Future<String> addMap(Model map) async {
    return await runTransaction((txn) async {
      var id = await txn.newDocId();
      txn.setMap(id, map);
      return id;
    });
  }

  /// Set a Map
  Future<void> setMap(String id, Model map) async {
    await runTransaction((txn) {
      txn.setMap(id, map);
    });
  }

  /// Set a document
  Future<void> setDoc(String id, T doc) {
    return setMap(id, doc.toMap());
  }

  @override
  String toString() => 'SyncedFsCollection(${refs.path})';
}
