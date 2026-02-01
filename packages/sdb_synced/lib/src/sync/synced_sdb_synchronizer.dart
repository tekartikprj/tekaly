import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekartik_app_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/list_utils.dart';

/// Synced db synchronized
class SyncedSdbSynchronizer extends SyncedDbSynchronizerCommon {
  SyncedSdb get db => super.dbCommon as SyncedSdb;
  SyncedSdbSynchronizer({
    required SyncedSdb db,
    required super.source,
    super.autoSync = false,
  }) : super(db: db);

  Future<void> close() async {}

  /// Get local dirty source records
  Future<List<SyncedSdbSyncSourceRecord>> getLocalDirtySourceRecords() async {
    var list = <SyncedSdbSyncSourceRecord>[];
    await db.syncTransaction(
      mode: SdbTransactionMode.readWrite,
      run: (txn) async {
        var dirtySyncRecords = await db.txnGetDirtySyncRecords(txn);
        for (var dirtySyncRecord in dirtySyncRecords) {
          // Try to get event if deleted
          var dataRecordRef = dirtySyncRecord.dataRecordRef;
          var snapshot = await dataRecordRef.get(txn);
          Map<String, Object?>? value;
          // Check and fix deleted
          if (dirtySyncRecord.deleted.v ?? false) {
            if (snapshot != null) {
              if (debugSyncedSync) {
                // ignore: avoid_print
                print(
                  'Found a record. Weird, deleted flag set for $snapshot - deleting record',
                );
              }
              await dataRecordRef.delete(txn);
            } else {
              // Ok
            }
          } else {
            if (snapshot == null) {
              if (debugSyncedSync) {
                // ignore: avoid_print
                print(
                  'Cannot find modified record. Weird, missing the deleted flag for $snapshot - setting the deleted flag',
                );
              }
              // important to set for later
              dirtySyncRecord.deleted.v = true;
              await db.txnPutSyncRecord(txn, dirtySyncRecord);
            } else {
              // ok
              value = snapshot.value;
            }
          }

          var sourceRecord = CvSyncedSourceRecord()
            //..syncTimestamp.v = dirtySyncRecord.syncTimestamp.v
            ..syncId.v = dirtySyncRecord.syncId.v
            ..record.v = (CvSyncedSourceRecordData()
              ..store.v = dirtySyncRecord.store.v
              ..key.v = dirtySyncRecord.key.v
              ..deleted.v = dirtySyncRecord.deleted.v == true
              ..value.v = value);
          list.add(
            SyncedSdbSyncSourceRecord()
              ..sourceRecord = sourceRecord
              ..syncRecord = dirtySyncRecord,
          );
        }
      },
    );
    return list;
  }

  /// Sync dirty records up
  Future<SyncedSyncStat> syncUp({bool fullSync = false}) async {
    return syncLock.synchronized(() {
      return _syncUp(fullSync: fullSync);
    });
  }

  /// Sync dirty records up
  Future<SyncedSyncStat> _syncUp({bool fullSync = false}) async {
    var stat = SyncedSyncStat();

    var dirtySourceRecords = await getLocalDirtySourceRecords();
    if (dirtySourceRecords.isNotEmpty) {
      for (var chunk in listChunk(dirtySourceRecords, stepLimitUp ?? 10)) {
        /// Multiple items at once locally
        var list = <SyncedSdbSyncSourceRecord>[];
        for (var syncSourceRecord in chunk) {
          list.add(
            SyncedSdbSyncSourceRecord()
              ..sourceRecord = await source.putSourceRecord(
                syncSourceRecord.sourceRecord!,
              )
              ..syncRecord = syncSourceRecord.syncRecord,
          );
        }

        await db.syncTransaction(
          mode: SdbTransactionMode.readWrite,
          run: (txn) async {
            for (var syncSourceRecord in list) {
              var isNew = syncSourceRecord.isNewLocalRecord;
              var responseRecord = syncSourceRecord.sourceRecord!;
              var originalSyncRecord = syncSourceRecord.syncRecord!;
              var newSyncRecord =
                  db.dbSyncRecordStoreRef.record(originalSyncRecord.id).cv()
                    ..deleted.v = responseRecord.record.v!.deleted.v
                    ..store.v = responseRecord.record.v!.store.v
                    ..key.v = responseRecord.record.v!.key.v
                    ..dirty.v = false
                    ..syncId.v = responseRecord.syncId.v
                    // id from the original syncRecord
                    //..id = originalSyncRecord.id
                    ..syncTimestamp.v = responseRecord.syncTimestamp.v
                    ..syncChangeId.v = responseRecord.syncChangeId.v;
              // copy from response
              await db.txnPutSyncRecord(txn, newSyncRecord);

              var dataRecordRef = newSyncRecord.dataRecordRef;

              /// Handle deleted case too. (!warning that could delete data at some point)
              if ((newSyncRecord.deleted.v ?? false) ||
                  (responseRecord.record.v!.value.isNull)) {
                stat.remoteDeletedCount++;
                await dataRecordRef.delete(txn);
              } else {
                if (isNew) {
                  stat.remoteCreatedCount++;
                } else {
                  stat.remoteUpdatedCount++;
                }
                await dataRecordRef.put(
                  txn,
                  asModel(responseRecord.record.v!.value.v ?? {}),
                );
              }
            }
          },
        );
      }
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncUp: $stat');
    }
    return stat;
  }
}

/// Synced sync source record
class SyncedSdbSyncSourceRecord extends SyncedSyncSourceRecordCommon {
  SdbSyncRecord? syncRecord;
}
