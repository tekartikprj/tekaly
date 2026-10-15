import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb.dart';
import 'package:tekaly_sdb_synced/src/sync/utils.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_common_utils/common_utils_import.dart';
import 'package:tekartik_app_common_utils/lazy_runner.dart';

/// Synced SDB synchronizer.
class SyncedSdbSynchronizer
    extends
        SyncedDbSynchronizerBase<
          SdbTransaction,
          SdbSyncRecord,
          SyncedSdbSyncSourceRecord
        > {
  /// Synced database.
  SyncedSdb get db => super.dbCommon as SyncedSdb;

  /// Synced SDB synchronizer constructor.
  ///
  /// Either a read-write [source], or a [readSource] and an optional
  /// [writeSource] must be given (see [SyncedDbSynchronizerCommon]):
  /// - [source] only: regular read-write synchronization.
  /// - [readSource] only: read-only synchronization (sync down only).
  /// - [readSource] and [writeSource]: hybrid, for example read from firestore
  ///   and write through an api.
  SyncedSdbSynchronizer({
    required SyncedSdb super.db,
    super.source,
    super.readSource,
    super.writeSource,
    super.autoSync = false,
    super.retryOptions,
  });

  late final _lazyLauncher = LazyRunner<SyncedSyncStat>(
    action: (count) async {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('start lazy sync');
      }
      return sync();
    },
  );

  /// Trigger a lazy sync, nothing is done once closed.
  @override
  Future<SyncedSyncStat> lazySync() async {
    if (closed) {
      // The lazy runner is closed, it would never answer.
      return SyncedSyncStat(notExecuted: true);
    }
    return (await _lazyLauncher.triggerAndWait());
  }

  /// Close synchronizer.
  ///
  /// Stops the automatic synchronization and waits for the running sync and
  /// the one queued behind it: the database can be closed once done, not
  /// before. Safe to call twice.
  @override
  Future<void> close() async {
    cancelAutoSync();
    await syncLock.synchronized(() {
      closeCommon();
    });
    // A sync requested while one was running runs after it, using the
    // database: wait for it too. Its error was reported (onSyncError) or
    // thrown to its caller.
    try {
      await closeSingleFlight();
    } catch (e) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Error while waiting for sync to terminate: $e');
      }
    }
    await _lazyLauncher.close();
  }

  SdbRecordRef<String, SdbModel> _recordRef(SyncedRecordKey key) =>
      SdbStoreRef<String, SdbModel>(key.store).record(key.key);

  @override
  Future<T> localSyncTransaction<T>(
    Future<T> Function(SdbTransaction txn) action,
  ) => db.syncTransaction(mode: SdbTransactionMode.readWrite, run: action);

  @override
  Future<List<SdbSyncRecord>> localGetDirtySyncRecords(SdbTransaction txn) =>
      db.txnGetDirtySyncRecords(txn);

  @override
  Future<bool> localHasDirtySyncRecords() async =>
      (await db.txnGetDirtySyncRecords(await db.database)).isNotEmpty;

  @override
  Future<List<SdbSyncRecord>> localGetSyncRecords() => db.getSyncRecords();

  @override
  Future<SdbSyncRecord?> localGetSyncRecordById(
    SdbTransaction client,
    int id,
  ) => db.scvSyncRecordStoreRef.record(id).get(client);

  @override
  Future<SdbSyncRecord?> localGetSyncRecordByKey(
    SdbTransaction client,
    SyncedRecordKey key,
  ) => db.getSyncRecord(client, _recordRef(key));

  @override
  int localSyncRecordId(SdbSyncRecord record) => record.id;

  @override
  SdbSyncRecord localNewSyncRecord([int? id]) =>
      id == null ? SdbSyncRecord() : db.scvSyncRecordStoreRef.record(id).cv();

  @override
  void localSetSyncRecordDeleted(SdbSyncRecord record, bool? deleted) {
    record.deleted.v = boolToInt(deleted);
  }

  @override
  void localSetSyncRecordDirty(SdbSyncRecord record, bool dirty) {
    record.dirty.v = boolToInt(dirty);
  }

  @override
  Future<void> localAddSyncRecord(
    SdbTransaction client,
    SdbSyncRecord record,
  ) async {
    await db.scvSyncRecordStoreRef.add(client, record);
  }

  @override
  Future<void> localPutSyncRecord(
    SdbTransaction client,
    SdbSyncRecord record,
  ) => db.txnPutSyncRecord(client, record);

  @override
  Future<void> localDeleteSyncRecord(SdbTransaction client, int id) =>
      db.scvSyncRecordStoreRef.record(id).delete(client);

  @override
  Future<Model?> localGetRecordValue(
    SdbTransaction client,
    SyncedRecordKey key,
  ) async {
    var snapshot = await _recordRef(key).get(client);
    return snapshot == null ? null : mapSdbToSyncedDb(snapshot.value);
  }

  @override
  Future<bool> localRecordExists(SdbTransaction client, SyncedRecordKey key) =>
      _recordRef(key).exists(client);

  @override
  Future<void> localPutRecordValue(
    SdbTransaction client,
    SyncedRecordKey key,
    Model value,
  ) async {
    await _recordRef(key).put(client, mapSyncedDbToSdb(value));
  }

  @override
  Future<void> localDeleteRecord(
    SdbTransaction client,
    SyncedRecordKey key,
  ) async {
    await _recordRef(key).delete(client);
  }

  @override
  Future<SdbSyncMetaInfo?> localGetSyncMetaInfo() async =>
      db.scvSyncMetaInfoRef.get(await db.database);

  @override
  Future<void> localSetSyncMetaInfo(
    SdbTransaction txn, {
    required int lastChangeId,
    required SyncedDbTimestamp? lastTimestamp,
    required int? sourceVersion,
  }) async {
    var metaInfo = db.scvSyncMetaInfoRef.cv()
      ..lastChangeId.v = lastChangeId
      ..lastTimestamp.v = lastTimestamp
      ..sourceVersion.setValue(sourceVersion);
    await db.setSyncMetaInfo(txn, metaInfo);
  }

  @override
  Stream<SdbSyncMetaInfo?> localOnSyncMetaInfo() => db.onSyncMetaInfo();

  @override
  Stream<bool> localOnDirty() => db.onDirty();

  /// Only the synced stores of the local schema: the records of a store this
  /// database does not know (newer schema) or of a local store are skipped.
  @override
  bool localShouldSyncStore(String store) =>
      syncedSdbShouldSyncStore(db, store);

  @override
  SyncedSdbSyncSourceRecord newSyncSourceRecord() =>
      SyncedSdbSyncSourceRecord();
}

/// Synced SDB sync source record.
class SyncedSdbSyncSourceRecord extends SyncedSyncSourceRecordCommon {
  /// Sync record.
  SdbSyncRecord? get syncRecord => super.syncRecordCommon as SdbSyncRecord?;
  set syncRecord(SdbSyncRecord? value) {
    super.syncRecordCommon = value;
  }
}
