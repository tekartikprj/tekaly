import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'model/db_sync_meta.dart';
import 'model/db_sync_record.dart';
import 'synced_db.dart';

/// Synced sync source record
class SyncedSyncSourceRecord extends SyncedSyncSourceRecordCommon {
  /// Set sync record
  set syncRecord(DbSyncRecord? value) {
    syncRecordCommon = value;
  }

  /// Get sync record
  DbSyncRecord? get syncRecord => syncRecordCommon as DbSyncRecord?;
}

/// Compat
typedef SyncedDbSourceSync = SyncedDbSynchronizer;

/// Synced db synchronized
class SyncedDbSynchronizer
    extends
        SyncedDbSynchronizerBase<
          Transaction,
          DbSyncRecord,
          SyncedSyncSourceRecord
        > {
  /// The database being synchronized
  late final SyncedDb db = dbCommon as SyncedDb;

  /// Synchronizer.
  ///
  /// Either a read-write [source], or a [readSource] and an optional
  /// [writeSource] must be given (see [SyncedDbSynchronizerCommon]).
  SyncedDbSynchronizer({
    required SyncedDb super.db,
    super.source,
    super.readSource,
    super.writeSource,
    super.autoSync = false,
    super.retryOptions,
  });

  /// Needed for autoSync.
  /// Wait for last sync to terminate.
  @override
  Future<void> close() async {
    cancelAutoSync();
    await syncLock.synchronized(() {
      closeCommon();
    });
    try {
      await closeSingleFlight();
    } catch (e, st) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Error while waiting for sync to terminate: $e $st');
      }
    }
  }

  /// Trigger a lazy sync
  @override
  FutureOr<SyncedSyncStat> lazySync() {
    return sync();
  }

  RecordRef<String, Map<String, Object?>> _recordRef(SyncedRecordKey key) =>
      stringMapStoreFactory.store(key.store).record(key.key);

  @override
  Future<T> localSyncTransaction<T>(
    Future<T> Function(Transaction txn) action,
  ) => db.syncTransaction(action);

  @override
  Future<List<DbSyncRecord>> localGetDirtySyncRecords(Transaction txn) =>
      db.txnGetDirtySyncRecords(txn);

  @override
  Future<bool> localHasDirtySyncRecords() async =>
      (await db.txnGetDirtySyncRecords(await db.database)).isNotEmpty;

  @override
  Future<List<DbSyncRecord>> localGetSyncRecords() => db.getSyncRecords();

  @override
  Future<DbSyncRecord?> localGetSyncRecordById(Transaction client, int id) =>
      db.dbSyncRecordStoreRef.record(id).get(client);

  @override
  Future<DbSyncRecord?> localGetSyncRecordByKey(
    Transaction client,
    SyncedRecordKey key,
  ) => db.getSyncRecord(client, _recordRef(key));

  @override
  int localSyncRecordId(DbSyncRecord record) => record.id;

  @override
  DbSyncRecord localNewSyncRecord([int? id]) =>
      id == null ? DbSyncRecord() : db.dbSyncRecordStoreRef.record(id).cv();

  @override
  void localSetSyncRecordDeleted(DbSyncRecord record, bool? deleted) {
    record.deleted.v = deleted;
  }

  @override
  void localSetSyncRecordDirty(DbSyncRecord record, bool dirty) {
    record.dirty.v = dirty;
  }

  @override
  Future<void> localAddSyncRecord(
    Transaction client,
    DbSyncRecord record,
  ) async {
    await db.dbSyncRecordStoreRef.add(client, record);
  }

  @override
  Future<void> localPutSyncRecord(Transaction client, DbSyncRecord record) =>
      db.txnPutSyncRecord(client, record);

  @override
  Future<void> localDeleteSyncRecord(Transaction client, int id) async {
    await db.dbSyncRecordStoreRef.record(id).delete(client);
  }

  @override
  Future<Model?> localGetRecordValue(Transaction client, SyncedRecordKey key) =>
      _recordRef(key).get(client);

  @override
  Future<bool> localRecordExists(
    Transaction client,
    SyncedRecordKey key,
  ) async => _recordRef(key).existsSync(client);

  @override
  Future<void> localPutRecordValue(
    Transaction client,
    SyncedRecordKey key,
    Model value,
  ) async {
    await _recordRef(key).put(client, value);
  }

  @override
  Future<void> localDeleteRecord(
    Transaction client,
    SyncedRecordKey key,
  ) async {
    await _recordRef(key).delete(client);
  }

  @override
  Future<DbSyncMetaInfo?> localGetSyncMetaInfo() async =>
      db.dbSyncMetaInfoRef.get(await db.database);

  @override
  Future<void> localSetSyncMetaInfo(
    Transaction txn, {
    required int lastChangeId,
    required SyncedDbTimestamp? lastTimestamp,
    required int? sourceVersion,
  }) async {
    var metaInfo = db.dbSyncMetaInfoRef.cv()
      ..lastChangeId.v = lastChangeId
      ..lastTimestamp.v = lastTimestamp
      ..sourceVersion.setValue(sourceVersion);
    await metaInfo.put(txn);
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('Setting meta Info $metaInfo');
    }
  }

  @override
  Stream<DbSyncMetaInfo?> localOnSyncMetaInfo() => db.onSyncMetaInfo();

  @override
  Stream<bool> localOnDirty() => db.onDirty();

  @override
  bool localShouldSyncStore(String store) => db.shouldSyncStore(store);

  @override
  SyncedSyncSourceRecord newSyncSourceRecord() => SyncedSyncSourceRecord();

  /// Wait for current sync to terminate
  @Deprecated('to remove')
  Future<void> lazyWaitSync() async {
    await waitSync();
  }
}
