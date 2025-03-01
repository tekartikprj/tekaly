import 'package:tekaly_firestore_synced/src/synced_fs_document.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_meta.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore/utils/auto_id_generator.dart';

class _TxnInfo<T extends CvFirestoreDocument> {
  final CvFirestoreTransaction txn;
  final SyncedFsCollection<T> collection;
  late final SyncedFsMetaInfoRecord meta;
  late int lastChangeId;

  _TxnInfo(this.txn, this.collection);

  Future<void> txnInit() async {
    meta = await txn.refGet(collection._metaInfoDocRef);
    lastChangeId = meta.lastChangeId.v ?? 0;
  }

  void txnEnd() {
    if (meta.lastChangeId.v != lastChangeId) {
      meta.lastChangeId.v = lastChangeId;
      txn.refSet(collection._metaInfoDocRef, meta);
    }
  }
}

/// Synced collection helper
class SyncedFsCollection<T extends CvFirestoreDocument> {
  /// Firestore instance
  final Firestore firestore;

  /// Hide it to prevent direct access
  final CvCollectionReference<T> _collection;
  late final CvDocumentReference<SyncedFsMetaInfoRecord> _metaInfoDocRef =
      CvCollectionReference<SyncedFsMetaInfoRecord>(
        '${_collection.path}_meta',
      ).doc('info');

  /// Constructor
  SyncedFsCollection({
    required this.firestore,
    required CvCollectionReference<T> collection,
  }) : _collection = collection {
    cvAddConstructors([
      SyncedFsMetaInfoRecord.new,
      CvSyncedFsDocumentSyncedInfo.new,
    ]);
  }

  /// Get a document
  Future<T> getDoc(String id) async {
    var ref = _collection.doc(id);
    var map = (await ref.raw(firestore).get()).dataOrNull;
    var doc = ref.cv();
    if (map != null) {
      var synced = _fullRecordMapSyncedInfo(map);
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

  CvSyncedFsDocumentSyncedInfo? _fullRecordMapSyncedInfo(Model map) {
    var synced = map[syncedFieldKey]?.anyAs<Map>();
    return synced?.cv<CvSyncedFsDocumentSyncedInfo>();
  }

  /// Get a document map if it exists
  Future<Model?> getMap(String id) async {
    var map = (await _collection.doc(id).raw(firestore).get()).dataOrNull;
    if (map != null) {
      var synced = _fullRecordMapSyncedInfo(map);
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

      var lastChangeId = ++txnInfo.lastChangeId;

      var ref = _collection.doc(id);
      var existingSnapshot = await txn.get(ref.raw(firestore));
      if (existingSnapshot.exists) {
        var newMap = Model.of(existingSnapshot.data);
        _mapUpdate(newMap, lastChangeId, deleted: true);
        txn.refSetMap(ref, newMap);

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

      var lastChangeId = ++txnInfo.lastChangeId;

      var ref = _collection.doc(uniqueId);
      txn.refSetMap(ref, _fullRecordModelFromMap(map, lastChangeId));

      txnInfo.txnEnd();
      return uniqueId;
    });
  }

  /// Set a Map
  Future<void> setMap(String id, Model map) async {
    return await firestore.cvRunTransaction((txn) async {
      var txnInfo = _TxnInfo<T>(txn, this);
      await txnInfo.txnInit();

      var lastChangeId = ++txnInfo.lastChangeId;

      var ref = _collection.doc(id);
      txn.refSetMap(ref, _fullRecordModelFromMap(map, lastChangeId));

      txnInfo.txnEnd();
    });
  }

  /// Set a document
  Future<void> setDoc(String id, T doc) {
    return setMap(id, doc.toMap());
  }
}
