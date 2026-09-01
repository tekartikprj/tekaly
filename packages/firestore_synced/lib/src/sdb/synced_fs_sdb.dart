import 'package:tekaly_firestore_synced/src/sdb/synced_fs_sdb_converter.dart';
import 'package:tekaly_firestore_synced/src/sdb/synced_fs_sdb_model.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_change.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_source.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

var _buildersInitialized = false;

/// Initialize the cv builders needed by the local mirror.
void cvInitSyncedFsSdbBuilders() {
  if (!_buildersInitialized) {
    _buildersInitialized = true;
    cvAddConstructors([SdbFsSyncMetaInfo.new, SdbFsSyncDeadLetter.new]);
  }
}

/// What one synchronization did.
class SyncedFsSdbSyncResult {
  /// True when the local store was rebuilt from a full snapshot.
  final bool fullSync;

  /// Records written locally.
  final int appliedCount;

  /// Records deleted locally.
  final int deletedCount;

  /// Changes sent to the dead letter queue.
  final int failedCount;

  /// Modification number reached, what the next synchronization resumes from.
  final int? lastChangeId;

  /// Result.
  SyncedFsSdbSyncResult({
    required this.fullSync,
    required this.appliedCount,
    required this.deletedCount,
    required this.failedCount,
    required this.lastChangeId,
  });

  /// True when nothing was applied.
  bool get isEmpty => appliedCount == 0 && deletedCount == 0;

  @override
  String toString() =>
      'SyncedFsSdbSyncResult(full: $fullSync, applied: $appliedCount, '
      'deleted: $deletedCount, failed: $failedCount, '
      'lastChangeId: $lastChangeId)';
}

/// One change ready to be applied locally, or the error that prevents it.
class _PreparedChange {
  final int? changeId;
  final String docId;
  final bool deleted;
  final SdbModel? value;
  final String? error;

  _PreparedChange({
    required this.changeId,
    required this.docId,
    required this.deleted,
    this.value,
    this.error,
  });

  bool get isFailed => error != null;
}

/// Mirrors a synced firestore collection into a local sdb store.
///
/// Documents are stored in [store] keyed by their firestore document id, with
/// the `synced` bookkeeping stripped. Applying a change is a plain put or
/// delete, so replaying the same change twice is harmless (idempotency), and a
/// change that cannot be applied goes to a dead letter queue instead of
/// blocking the synchronization.
///
/// ```dart
/// var schema = SdbDatabaseSchema(
///   stores: [itemStoreRef.schema(), ...syncedFsSdbSchema.stores],
/// );
/// var db = await factory.openDatabase(
///   'app.db',
///   options: SdbOpenDatabaseOptions(version: 1, schema: schema),
/// );
/// var synchronizer = SyncedFsSdbSynchronizer(
///   source: SyncedFsFirestoreSource(firestore: firestore, path: 'item'),
///   database: db,
///   store: itemStoreRef,
/// );
/// await synchronizer.sync();
/// ```
class SyncedFsSdbSynchronizer {
  /// The remote collection to synchronize from.
  final SyncedFsSource source;

  /// The local database, its schema must include [syncedFsSdbSchema] stores.
  final SdbDatabase database;

  /// The local store mirroring the collection.
  final SdbStoreRef<String, SdbModel> store;

  /// How many change log entries are read at once.
  final int stepLimit;

  /// Synchronizer.
  SyncedFsSdbSynchronizer({
    required this.source,
    required this.database,
    required this.store,
    this.stepLimit = syncedFsDefaultStepLimit,
  }) {
    cvInitSyncedFsSdbBuilders();
  }

  late final _metaRecordRef = syncedFsSdbMetaStoreRef.record(store.name);

  List<String> get _storeNames => [
    store.name,
    syncedFsSdbMetaStoreName,
    syncedFsSdbDeadLetterStoreName,
  ];

  /// Where the local mirror stands, null before the first synchronization.
  Future<SdbFsSyncMetaInfo?> getSyncMetaInfo({SdbClient? client}) =>
      _metaRecordRef.get(client ?? database);

  /// Last modification number applied locally, null before the first
  /// synchronization.
  Future<int?> getLastChangeId() async =>
      (await getSyncMetaInfo())?.lastChangeId.v;

  /// The changes that could not be applied.
  Future<List<SdbFsSyncDeadLetter>> getDeadLetters({SdbClient? client}) async {
    return await syncedFsSdbDeadLetterByStoreIndexRef
        .record(store.name)
        .findObjects(client ?? database);
  }

  /// Synchronize the local store with the remote collection.
  ///
  /// Does a full resynchronization when the local mirror is new, bound to
  /// another source, left behind a change log truncation, or when the source
  /// version was bumped. Otherwise replays the change log from the last
  /// applied modification number.
  Future<SyncedFsSdbSyncResult> sync() async {
    var remoteMeta = await source.getMetaInfo();
    var remoteVersion = remoteMeta?.version.v ?? 1;
    var localMeta = await getSyncMetaInfo();
    var localChangeId = localMeta?.lastChangeId.v;

    var fullSync =
        localMeta == null ||
        localMeta.source.v != source.sourceId ||
        (localMeta.sourceVersion.v ?? 1) != remoteVersion ||
        (remoteMeta?.minIncrementalChangeId.v ?? 0) > (localChangeId ?? 0);

    var appliedCount = 0;
    var deletedCount = 0;
    var failedCount = 0;
    var lastChangeId = fullSync ? null : localChangeId;

    if (fullSync) {
      var snapshot = await source.getSnapshot();
      var result = await _applySnapshot(snapshot, version: remoteVersion);
      appliedCount += result.appliedCount;
      deletedCount += result.deletedCount;
      failedCount += result.failedCount;
      lastChangeId = snapshot.lastChangeId ?? 0;
    }

    while (true) {
      var list = await source.getChangeList(
        afterChangeId: lastChangeId,
        limit: stepLimit,
      );
      if (list.isEmpty) {
        break;
      }
      var result = await _applyChanges(list, version: remoteVersion);
      appliedCount += result.appliedCount;
      deletedCount += result.deletedCount;
      failedCount += result.failedCount;
      lastChangeId = list.lastChangeId ?? lastChangeId;
    }

    /// Always write the meta, so that an empty first synchronization is
    /// recorded (and does not trigger a full one next time).
    await database.inTransaction(
      storeNames: [syncedFsSdbMetaStoreName],
      mode: SdbTransactionMode.readWrite,
      run: (txn) => _txnPutMeta(
        txn,
        lastChangeId: lastChangeId ?? 0,
        version: remoteVersion,
      ),
    );

    return SyncedFsSdbSyncResult(
      fullSync: fullSync,
      appliedCount: appliedCount,
      deletedCount: deletedCount,
      failedCount: failedCount,
      lastChangeId: lastChangeId,
    );
  }

  /// Retry the dead letters, dropping the ones that apply.
  ///
  /// Fetches a fresh snapshot of each queued document, so a change that failed
  /// because of a transient problem, or a document fixed since, is picked up.
  Future<SyncedFsSdbSyncResult> retryDeadLetters() async {
    var deadLetters = await getDeadLetters();
    if (deadLetters.isEmpty) {
      return SyncedFsSdbSyncResult(
        fullSync: false,
        appliedCount: 0,
        deletedCount: 0,
        failedCount: 0,
        lastChangeId: await getLastChangeId(),
      );
    }
    var docIds = deadLetters.map((e) => e.docId.v!).toSet().toList();
    var snapshot = await source.getSnapshot(docIds: docIds);
    var prepared = <String, _PreparedChange>{};
    for (var docId in docIds) {
      var map = snapshot.docs[docId];
      prepared[docId] = map == null
          ? _PreparedChange(changeId: null, docId: docId, deleted: true)
          : _prepare(changeId: null, docId: docId, deleted: false, data: map);
    }

    var appliedCount = 0;
    var deletedCount = 0;
    var failedCount = 0;
    await database.inTransaction(
      storeNames: _storeNames,
      mode: SdbTransactionMode.readWrite,
      run: (txn) async {
        for (var deadLetter in deadLetters) {
          var change = prepared[deadLetter.docId.v!]!;
          if (change.isFailed) {
            failedCount++;
            deadLetter
              ..retryCount.v = (deadLetter.retryCount.v ?? 0) + 1
              ..error.v = change.error
              ..timestamp.v = SdbTimestamp.now();
            await deadLetter.put(txn);
            continue;
          }
          if (change.deleted) {
            await store.record(change.docId).delete(txn);
            deletedCount++;
          } else {
            await store.record(change.docId).put(txn, change.value!);
            appliedCount++;
          }
          await deadLetter.delete(txn);
        }
      },
    );
    return SyncedFsSdbSyncResult(
      fullSync: false,
      appliedCount: appliedCount,
      deletedCount: deletedCount,
      failedCount: failedCount,
      lastChangeId: await getLastChangeId(),
    );
  }

  /// Forget everything known locally, the next [sync] does a full one.
  Future<void> reset() async {
    await database.inTransaction(
      storeNames: _storeNames,
      mode: SdbTransactionMode.readWrite,
      run: (txn) async {
        await store.delete(txn);
        await _metaRecordRef.delete(txn);
        for (var deadLetter in await getDeadLetters(client: txn)) {
          await deadLetter.delete(txn);
        }
      },
    );
  }

  /// Apply a full snapshot: what is not in it any more is deleted locally.
  Future<SyncedFsSdbSyncResult> _applySnapshot(
    SyncedFsSnapshot snapshot, {
    required int version,
  }) async {
    var prepared = <_PreparedChange>[
      for (var entry in snapshot.docs.entries)
        _prepare(
          changeId: null,
          docId: entry.key,
          deleted: false,
          data: entry.value,
        ),
    ];
    var appliedCount = 0;
    var deletedCount = 0;
    var failedCount = 0;
    await database.inTransaction(
      storeNames: _storeNames,
      mode: SdbTransactionMode.readWrite,
      run: (txn) async {
        var existingKeys = (await store.findRecords(
          txn,
        )).map((snapshot) => snapshot.ref.key).toSet();
        for (var change in prepared) {
          /// Keep the (stale) local record when the new content cannot be
          /// stored, it is better than dropping it silently.
          existingKeys.remove(change.docId);
          if (change.isFailed) {
            await _txnAddDeadLetter(txn, change);
            failedCount++;
            continue;
          }
          await store.record(change.docId).put(txn, change.value!);
          appliedCount++;
        }
        for (var key in existingKeys) {
          await store.record(key).delete(txn);
          deletedCount++;
        }
        await _txnPutMeta(
          txn,
          lastChangeId: snapshot.lastChangeId ?? 0,
          version: version,
        );
      },
    );
    return SyncedFsSdbSyncResult(
      fullSync: true,
      appliedCount: appliedCount,
      deletedCount: deletedCount,
      failedCount: failedCount,
      lastChangeId: snapshot.lastChangeId,
    );
  }

  Future<SyncedFsSdbSyncResult> _applyChanges(
    SyncedFsChangeList list, {
    required int version,
  }) async {
    /// Entries written without their content, fetch the documents.
    var toFetch = list.list
        .where((change) => change.needsSnapshot)
        .map((change) => change.docId.v!)
        .toSet()
        .toList();
    var fetched = toFetch.isEmpty
        ? null
        : await source.getSnapshot(docIds: toFetch);

    var prepared = <_PreparedChange>[
      for (var change in list.list)
        _prepareChange(change, fetched: fetched?.docs),
    ];

    var appliedCount = 0;
    var deletedCount = 0;
    var failedCount = 0;
    await database.inTransaction(
      storeNames: _storeNames,
      mode: SdbTransactionMode.readWrite,
      run: (txn) async {
        for (var change in prepared) {
          if (change.isFailed) {
            await _txnAddDeadLetter(txn, change);
            failedCount++;
            continue;
          }
          if (change.deleted) {
            await store.record(change.docId).delete(txn);
            deletedCount++;
          } else {
            await store.record(change.docId).put(txn, change.value!);
            appliedCount++;
          }
        }
        if (list.lastChangeId != null) {
          await _txnPutMeta(
            txn,
            lastChangeId: list.lastChangeId!,
            version: version,
          );
        }
      },
    );
    return SyncedFsSdbSyncResult(
      fullSync: false,
      appliedCount: appliedCount,
      deletedCount: deletedCount,
      failedCount: failedCount,
      lastChangeId: list.lastChangeId,
    );
  }

  _PreparedChange _prepareChange(
    CvSyncedFsChangeRecord change, {
    Map<String, Model>? fetched,
  }) {
    var docId = change.docId.v!;
    if (change.deleted.v == true) {
      return _PreparedChange(
        changeId: change.changeId.v,
        docId: docId,
        deleted: true,
      );
    }
    var data = change.data.v ?? fetched?[docId];
    if (data == null) {
      /// The entry has no content and the document is gone, treat it as a
      /// deletion rather than failing.
      return _PreparedChange(
        changeId: change.changeId.v,
        docId: docId,
        deleted: true,
      );
    }
    return _prepare(
      changeId: change.changeId.v,
      docId: docId,
      deleted: false,
      data: data,
    );
  }

  _PreparedChange _prepare({
    required int? changeId,
    required String docId,
    required bool deleted,
    Model? data,
  }) {
    try {
      return _PreparedChange(
        changeId: changeId,
        docId: docId,
        deleted: deleted,
        value: deleted ? null : firestoreMapToSdb(data!),
      );
    } catch (e) {
      return _PreparedChange(
        changeId: changeId,
        docId: docId,
        deleted: deleted,
        error: e.toString(),
      );
    }
  }

  Future<void> _txnAddDeadLetter(
    SdbTransaction txn,
    _PreparedChange change,
  ) async {
    var existing = (await getDeadLetters(
      client: txn,
    )).where((deadLetter) => deadLetter.docId.v == change.docId);
    if (existing.isNotEmpty) {
      for (var deadLetter in existing) {
        deadLetter
          ..retryCount.v = (deadLetter.retryCount.v ?? 0) + 1
          ..changeId.v = change.changeId ?? deadLetter.changeId.v
          ..error.v = change.error
          ..timestamp.v = SdbTimestamp.now();
        await deadLetter.put(txn);
      }
      return;
    }
    await syncedFsSdbDeadLetterStoreRef.add(
      txn,
      SdbFsSyncDeadLetter()
        ..store.v = store.name
        ..changeId.v = change.changeId
        ..docId.v = change.docId
        ..deleted.v = change.deleted
        ..error.v = change.error
        ..retryCount.v = 0
        ..timestamp.v = SdbTimestamp.now(),
    );
  }

  Future<void> _txnPutMeta(
    SdbTransaction txn, {
    required int lastChangeId,
    required int version,
  }) async {
    var meta = _metaRecordRef.cv()
      ..source.v = source.sourceId
      ..sourceVersion.v = version
      ..lastChangeId.v = lastChangeId
      ..lastTimestamp.v = SdbTimestamp.now();
    await meta.put(txn);
  }

  @override
  String toString() =>
      'SyncedFsSdbSynchronizer(${source.sourceId} -> ${store.name})';
}
