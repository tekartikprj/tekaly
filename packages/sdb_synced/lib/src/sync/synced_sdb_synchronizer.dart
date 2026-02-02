import 'dart:math';

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
  @override
  Future<SyncedSyncStat> doSyncUp({bool fullSync = false}) async {
    var stat = SyncedSyncStat();

    var dirtySourceRecords = await getLocalDirtySourceRecords();
    if (dirtySourceRecords.isNotEmpty) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('syncUp: found ${dirtySourceRecords.length} dirty records');
      }
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
              if (debugSyncedSync) {
                // ignore: avoid_print
                print(
                  'syncUp: putting sync record ${newSyncRecord.store.v} - ${newSyncRecord.key.v} : $newSyncRecord',
                );
              }
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
                var data = asModel(responseRecord.record.v!.value.v ?? {});
                if (debugSyncedSync) {
                  // ignore: avoid_print
                  print(
                    'syncUp: putting data record ${dataRecordRef.store.name} - ${dataRecordRef.key} : $data',
                  );
                }
                await dataRecordRef.put(txn, data);
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

  /// Sync dirty records up
  @override
  Future<SyncedSyncStat> doSyncDown() async {
    var db = await this.db.database;
    var stat = SyncedSyncStat();

    var localMetaSyncInfo = (await this.db.dbSyncMetaInfoRef.get(db));
    var hasInitialLastChangeId = localMetaSyncInfo?.lastChangeId.v != null;
    var initialLastChangeIdOrNull = localMetaSyncInfo?.lastChangeId.v;
    var initialLastChangeId = initialLastChangeIdOrNull ?? -1;
    var fullSync = initialLastChangeId == -1;

    var newLastChangeId = initialLastChangeIdOrNull ?? 0;
    ScvTimestamp? newLastTimestamp;
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('localMetaSyncInfo: $localMetaSyncInfo');
    }

    var fetchLastChangeId = initialLastChangeId;

    /// Read with deleted
    final initialSourceMeta = await getSourceMetaInfo();

    var needReFetch = false;
    var newSourceVersion = false;

    if ((initialSourceMeta?.version.v ?? 0) !=
        (localMetaSyncInfo?.sourceVersion.v ?? 0)) {
      newSourceVersion = true;
      fullSync = true;
      fetchLastChangeId = 0;
    }
    // If reading records is empty, we can use this number.
    var sourceMetaLastChangeNum = initialSourceMeta?.lastChangeId.v;
    var sourceMeta = initialSourceMeta;
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('sourceMeta: $sourceMeta');
    }

    /// Full sync min incremental change does not match
    if (initialLastChangeId < (sourceMeta?.minIncrementalChangeId.v ?? 0)) {
      needReFetch = true;
    }

    /// Full sync new version!
    if (initialLastChangeId != 0 && newSourceVersion) {
      needReFetch = true;
    }

    if (needReFetch) {
      fullSync = true;
    }

    SyncedSourceRecordList dirtyRemoteSourceRecords;
    bool? includeDeleted;
    int? afterChangeId;
    if (fullSync) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print(
          'fullSync: $fullSync ($initialLastChangeId < ${sourceMeta?.lastChangeId.v}): last fetch: $fetchLastChangeId',
        );
      }
      afterChangeId = fetchLastChangeId;
    } else {
      includeDeleted = true;
      afterChangeId = initialLastChangeId;
    }
    dirtyRemoteSourceRecords = await source.getAllSourceRecordList(
      afterChangeId: afterChangeId,
      stepLimit: stepLimitDown,
      includeDeleted: includeDeleted,
    );
    if (debugSyncedSync) {
      // ignore: avoid_print
      print(
        'fetching ${dirtyRemoteSourceRecords.length} records after $fetchLastChangeId (${dirtyRemoteSourceRecords.lastChangeId})',
      );
    }

    // only for full sync
    List<SdbSyncRecord>? localSyncRecords;
    Map<SyncedRecordKey, SdbSyncRecord>? localMap;

    if (fullSync) {
      localSyncRecords = await this.db.getSyncRecords();
      localMap = <SyncedRecordKey, SdbSyncRecord>{};
      for (var syncRecord in localSyncRecords) {
        localMap[syncRecord.syncedKey] = syncRecord;
      }
    }

    /// Remote wins!
    await this.db.syncTransaction(
      mode: SdbTransactionMode.readWrite,
      run: (txn) async {
        for (var remoteRecord in dirtyRemoteSourceRecords.list) {
          var remoteRecordData = remoteRecord.record.v;

          if (remoteRecordData?.store.v == null ||
              remoteRecordData?.key.v == null ||
              remoteRecord.syncTimestamp.v == null ||
              remoteRecord.syncChangeId.v == null) {
            if (debugSyncedSync) {
              // ignore: avoid_print
              print('invalid dirty: $remoteRecord');
            }
            continue;
          }

          /// Update last change id
          newLastChangeId = remoteRecord.syncChangeId.v!;
          newLastTimestamp = remoteRecord.syncTimestamp.v!;

          SdbSyncRecord? local;
          var syncedKey = remoteRecord.syncedKey;

          if (fullSync) {
            local = localMap![syncedKey];
          } else {
            local = await this.db.getSyncRecord(
              db,
              SdbStoreRef<String, SdbModel>(
                syncedKey.store,
              ).record(syncedKey.key),
            );
          }
          if (local == null) {
            if (!(remoteRecordData!.isDeleted)) {
              // create
              await _syncSourceRecordDown(txn, remoteRecord, stat);
            }
          } else if (local.syncTimestamp.v != remoteRecord.syncTimestamp.v ||
              newSourceVersion) {
            //if (newSourceVersion || !remoteRecordData!.isDeleted) {
            // update
            await _syncSourceRecordDown(txn, remoteRecord, stat);
            localMap?.remove(syncedKey);
            //} else {
            // we'll delete it later
            //          }
          } else {
            // Ok, don't delete it
            localMap?.remove(syncedKey);
          }
        }
        // Clean up for full sync
        if (fullSync) {
          for (var localDbSync in localMap!.values) {
            if (debugSyncedSync) {
              // ignore: avoid_print
              print('deleting: $localDbSync');
            }
            await _deleteLocalRecord(txn, localDbSync);
            stat.localDeletedCount++;
          }
        }

        // Use meta if available
        if (dirtyRemoteSourceRecords.lastChangeId != null) {
          newLastChangeId = dirtyRemoteSourceRecords.lastChangeId!;
        }
        if (dirtyRemoteSourceRecords.isEmpty) {
          if (sourceMetaLastChangeNum != null) {
            newLastChangeId = max(newLastChangeId, sourceMetaLastChangeNum);
          }
        }
        Future<void> saveMetaInfo() async {
          var metaInfo = this.db.dbSyncMetaInfoRef.cv()
            ..lastChangeId.v = newLastChangeId
            ..lastTimestamp.v = newLastTimestamp
            ..sourceVersion.setValue(initialSourceMeta?.version.v);
          await metaInfo.put(txn);
          if (debugSyncedSync) {
            // ignore: avoid_print
            print('Setting meta Info $metaInfo');
          }
        }

        if (newLastChangeId != initialLastChangeId ||
            (initialSourceMeta?.version.v !=
                localMetaSyncInfo?.sourceVersion.v)) {
          await saveMetaInfo();
        } else if (newLastChangeId == 0 &&
            initialLastChangeId == 0 &&
            !hasInitialLastChangeId) {
          await saveMetaInfo();
        }
      },
    );

    if (!_firstSyncDoneCompleter.isCompleted) {
      _firstSyncDoneCompleter.complete();
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncDown: $stat');
    }
    return stat;
  }

  final _firstSyncDoneCompleter = Completer<void>.sync();
  Future<void> _syncSourceRecordDown(
    SdbClient client,
    CvSyncedSourceRecord remoteRecord,
    SyncedSyncStat stat,
  ) async {
    await db.dbSyncRecordStoreRef.add(
      client,
      (SdbSyncRecord()
        ..syncId.v = remoteRecord.syncId.v
        ..syncTimestamp.v = remoteRecord.syncTimestamp.v
        ..store.v = remoteRecord.record.v!.store.v
        ..key.v = remoteRecord.record.v!.key.v
        ..deleted.v = remoteRecord.record.v!.deleted.v),
    );

    var ref = SdbStoreRef<String, SdbModel>(
      remoteRecord.record.v!.store.v!,
    ).record(remoteRecord.record.v!.key.v!);
    if (remoteRecord.isDeleted) {
      stat.localDeletedCount++;
      await ref.delete(client);
    } else {
      if (await ref.exists(client)) {
        stat.localUpdatedCount++;
      } else {
        stat.localCreatedCount++;
      }
      await ref.put(
        client,
        remoteRecord.record.v!.value.v!.cast<String, Object?>(),
      );
    }
  }

  Future<void> _deleteLocalRecord(
    SdbClient client,
    SdbSyncRecord syncRecord,
  ) async {
    // create
    await db.dbSyncRecordStoreRef.record(syncRecord.id).delete(client);
    await SdbStoreRef<String, SdbModel>(
      syncRecord.store.v!,
    ).record(syncRecord.key.v!).delete(client);
  }

  /*
  /// Wait for current sync to terminate
  Future<void> lazyWaitSync() async {
    await _lazyLauncher.waitCurrent();
  }*/
}

/// Synced sync source record
class SyncedSdbSyncSourceRecord extends SyncedSyncSourceRecordCommon {
  SdbSyncRecord? syncRecord;
}
