import 'dart:math';

import 'package:collection/collection.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/list_utils.dart';
import 'package:tekartik_common_utils/stream/stream_join.dart';

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
class SyncedDbSynchronizer extends SyncedDbSynchronizerCommon {
  /// The database being synchronized
  late final SyncedDb db = dbCommon as SyncedDb;

  /// Get local dirty source records
  Future<List<SyncedSyncSourceRecord>> getLocalDirtySourceRecords() async {
    var list = <SyncedSyncSourceRecord>[];
    await db.syncTransaction((txn) async {
      var dirtySyncRecords = await db.txnGetDirtySyncRecords(txn);
      for (var dirtySyncRecord in dirtySyncRecords) {
        list.add(await _txnGetDirtySyncSourceRecord(txn, dirtySyncRecord));
      }
    });
    return list;
  }

  /// Reload the source records to push for the given sync record ids,
  /// skipping the ones no longer dirty.
  Future<List<SyncedSyncSourceRecord>> _getLocalDirtySourceRecordsByIds(
    Iterable<int> syncRecordIds,
  ) async {
    var list = <SyncedSyncSourceRecord>[];
    await db.syncTransaction((txn) async {
      for (var id in syncRecordIds) {
        var syncRecord = await db.dbSyncRecordStoreRef.record(id).get(txn);
        if (syncRecord == null || !syncRecord.isDirty) {
          continue;
        }
        list.add(await _txnGetDirtySyncSourceRecord(txn, syncRecord));
      }
    });
    return list;
  }

  /// Build the source record to push for a dirty sync record.
  Future<SyncedSyncSourceRecord> _txnGetDirtySyncSourceRecord(
    Transaction txn,
    DbSyncRecord dirtySyncRecord,
  ) async {
    // Try to get event if deleted
    var dataRecordRef = dirtySyncRecord.dataRecordRef;
    var snapshot = await dataRecordRef.getSnapshot(txn);
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
    return SyncedSyncSourceRecord()
      ..sourceRecord = sourceRecord
      ..syncRecord = dirtySyncRecord;
  }

  // Auto sync subscription
  StreamSubscription? _autoSyncSourceSubscription;
  StreamSubscription? _autoSyncDbSubscription;

  /// Synchronizer.
  ///
  /// Either a read-write [source], or a [readSource] and an optional
  /// [writeSource] must be given (see [SyncedDbSynchronizerCommon]).
  SyncedDbSynchronizer({
    required SyncedDb db,
    super.source,
    super.readSource,
    super.writeSource,
    super.autoSync = false,
    super.retryOptions,
  }) : super(db: db) {
    if (autoSync) {
      _autoSyncSourceSubscription =
          streamJoin2(
            // An unreachable source reports an error rather than its meta
            // info: it must start the retries, it never reaches the join.
            readSource.onMetaInfo().handleError(handleAutoSyncSourceError),
            db.onSyncMetaInfo(),
          ).listen((
            event,
          ) {
            var remote = event.$1;
            var local = event.$2;
            var remoteLastChangeId = remote?.lastChangeId.v ?? 0;
            var localLastChangeId = local?.lastChangeId.v ?? 0;
            // devPrint('remote $remote, local: $local');
            if (remoteLastChangeId != localLastChangeId) {
              triggerAutoSync();
            } else if (remoteLastChangeId == 0 && localLastChangeId == 0) {
              triggerAutoSync();
            }
          });
      // Local changes can only be pushed when there is a write source.
      if (!isReadOnly) {
        _autoSyncDbSubscription = db.onDirty().listen((dirty) {
          // devPrint('localDirty $dirty');
          if (dirty) {
            triggerAutoSync();
          }
        });
      }
      // The joined meta info stream above only emits once the source has
      // reported its meta info, which never happens while the source is
      // unreachable: make sure a first synchronization is attempted anyway.
      startFirstSyncWatchdog();
    }
  }

  @override
  FutureOr<SyncedSyncStat> autoSyncAction() => lazySync();

  /// Needed for autoSync.
  /// Wait for last sync to terminate.
  Future<void> close() async {
    _autoSyncSourceSubscription?.cancel().unawait();
    _autoSyncDbSubscription?.cancel().unawait();
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
  FutureOr<SyncedSyncStat> lazySync() {
    return sync();
  }

  /// Sync dirty records up
  @override
  Future<SyncedSyncStat> doSyncUp({bool fullSync = false}) async {
    var stat = SyncedSyncStat();
    if (isReadOnly) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('syncUp: read-only, skipped');
      }
      return stat;
    }

    var dirtySourceRecords = await getLocalDirtySourceRecords();
    if (dirtySourceRecords.isNotEmpty) {
      await _pushLocalDirtySourceRecords(dirtySourceRecords, stat);
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncUp: $stat');
    }
    return stat;
  }

  /// Push local dirty source records up, updating [stat].
  Future<void> _pushLocalDirtySourceRecords(
    List<SyncedSyncSourceRecord> dirtySourceRecords,
    SyncedSyncStat stat,
  ) async {
    var writeSource = this.writeSource;
    if (writeSource == null) {
      // Read-only: local changes stay dirty.
      return;
    }
    // Loop until no pushed record gets changed locally during the push
    while (dirtySourceRecords.isNotEmpty) {
      /// Sync record ids of records changed locally during putSourceRecord
      var changedSyncRecordIds = <int>[];
      for (var chunk in listChunk(dirtySourceRecords, stepLimitUp ?? 10)) {
        /// Records actually sent to the source
        var sentList = <SyncedSyncSourceRecord>[];

        /// Put responses, one per sent record
        var list = <SyncedSyncSourceRecord>[];

        /// Remote records winning over the local dirty change (their change
        /// num is strictly greater), to apply locally instead of pushing.
        var remoteWinList = <SyncedSyncSourceRecord>[];
        for (var syncSourceRecord in chunk) {
          /// Remote wins if the remote change num is strictly greater than
          /// the last change num seen locally: read the remote record first.
          var localChangeNum = syncSourceRecord.syncRecord!.syncChangeId.v ?? 0;
          var remoteRecord = await readSource.getSourceRecord(
            syncSourceRecord.sourceRecord!.ref,
          );
          var remoteChangeNum = remoteRecord?.syncChangeId.v ?? 0;
          if (remoteRecord != null && remoteChangeNum > localChangeNum) {
            if (debugSyncedSync) {
              // ignore: avoid_print
              print(
                'syncUp: remote record is newer ($remoteChangeNum > $localChangeNum), remote wins $remoteRecord',
              );
            }
            remoteWinList.add(
              SyncedSyncSourceRecord()
                ..sourceRecord = remoteRecord
                ..syncRecord = syncSourceRecord.syncRecord,
            );
            continue;
          }
          sentList.add(syncSourceRecord);
          list.add(
            SyncedSyncSourceRecord()
              ..sourceRecord = await writeSource.putSourceRecord(
                syncSourceRecord.sourceRecord!,
              )
              ..syncRecord = syncSourceRecord.syncRecord,
          );
        }

        await db.syncTransaction((txn) async {
          /// Apply the remote records winning over the local dirty change
          /// (the local change is discarded, the dirty flag cleared).
          for (var remoteWin in remoteWinList) {
            await _syncSourceRecordDown(
              txn,
              remoteWin.sourceRecord!,
              stat,
              existingSyncRecord: remoteWin.syncRecord,
            );
          }
          for (var i = 0; i < list.length; i++) {
            var syncSourceRecord = list[i];

            /// The record data that was sent to the source
            var sentRecordData = sentList[i].sourceRecord!.record.v!;
            var isNew = syncSourceRecord.isNewLocalRecord;
            var responseRecord = syncSourceRecord.sourceRecord!;
            var originalSyncRecord = syncSourceRecord.syncRecord!;
            var syncRecordRef = db.dbSyncRecordStoreRef.record(
              originalSyncRecord.id,
            );
            var newSyncRecord = syncRecordRef.cv()
              ..deleted.v = responseRecord.record.v!.deleted.v
              ..store.v = responseRecord.record.v!.store.v
              ..key.v = responseRecord.record.v!.key.v
              ..dirty.v = false
              ..syncId.v = responseRecord.syncId.v
              // id from the original syncRecord
              //..id = originalSyncRecord.id
              ..syncTimestamp.v = responseRecord.syncTimestamp.v
              ..syncChangeId.v = responseRecord.syncChangeId.v;
            var dataRecordRef = newSyncRecord.dataRecordRef;

            /// Check whether another local change happened during
            /// putSourceRecord, i.e. the current local data no longer
            /// matches what was sent.
            var currentSnapshot = await dataRecordRef.getSnapshot(txn);
            bool changedDuringPut;
            if (sentRecordData.deleted.v ?? false) {
              changedDuringPut = currentSnapshot != null;
            } else {
              changedDuringPut =
                  currentSnapshot == null ||
                  !const DeepCollectionEquality().equals(
                    currentSnapshot.value,
                    sentRecordData.value.v,
                  );
            }
            if (changedDuringPut) {
              // Keep the record dirty and the local data untouched, only
              // save the sync info from the response so that the next
              // push updates the same source record.
              var currentSyncRecord =
                  await syncRecordRef.get(txn) ??
                  (newSyncRecord..deleted.v = currentSnapshot == null);
              currentSyncRecord
                ..dirty.v = true
                ..syncId.v = responseRecord.syncId.v
                ..syncTimestamp.v = responseRecord.syncTimestamp.v
                ..syncChangeId.v = responseRecord.syncChangeId.v;
              if (debugSyncedSync) {
                // ignore: avoid_print
                print(
                  'syncUp: record changed during push, will push again $currentSyncRecord',
                );
              }
              await db.txnPutSyncRecord(txn, currentSyncRecord);
              changedSyncRecordIds.add(originalSyncRecord.id);
              if ((newSyncRecord.deleted.v ?? false) ||
                  (responseRecord.record.v!.value.isNull)) {
                stat.remoteDeletedCount++;
              } else if (isNew) {
                stat.remoteCreatedCount++;
              } else {
                stat.remoteUpdatedCount++;
              }
              continue;
            }
            // copy from response
            await db.txnPutSyncRecord(txn, newSyncRecord);

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
        });
      }
      if (changedSyncRecordIds.isEmpty) {
        break;
      }
      if (debugSyncedSync) {
        // ignore: avoid_print
        print(
          'syncUp: ${changedSyncRecordIds.length} record(s) changed during push, pushing again',
        );
      }
      dirtySourceRecords = await _getLocalDirtySourceRecordsByIds(
        changedSyncRecordIds,
      );
    }
  }

  Future<void> _syncSourceRecordDown(
    DatabaseClient client,
    CvSyncedSourceRecord remoteRecord,
    SyncedSyncStat stat, {
    DbSyncRecord? existingSyncRecord,
  }) async {
    var syncRecord =
        (existingSyncRecord == null
              ? DbSyncRecord()
              : db.dbSyncRecordStoreRef.record(existingSyncRecord.id).cv())
          ..syncId.v = remoteRecord.syncId.v
          ..syncTimestamp.v = remoteRecord.syncTimestamp.v
          ..syncChangeId.v = remoteRecord.syncChangeId.v
          ..store.v = remoteRecord.record.v!.store.v
          ..key.v = remoteRecord.record.v!.key.v
          ..deleted.v = remoteRecord.record.v!.deleted.v ?? false;
    if (existingSyncRecord == null) {
      await db.dbSyncRecordStoreRef.add(client, syncRecord);
    } else {
      // Overwrite the existing sync record, clearing the dirty flag
      // (remote wins).
      syncRecord.dirty.v = false;
      await db.txnPutSyncRecord(client, syncRecord);
    }

    var ref = stringMapStoreFactory
        .store(remoteRecord.record.v!.store.v)
        .record(remoteRecord.record.v!.key.v!);
    if (remoteRecord.isDeleted) {
      stat.localDeletedCount++;
      await ref.delete(client);
    } else {
      if (ref.existsSync(client)) {
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
    DatabaseClient client,
    DbSyncRecord syncRecord,
  ) async {
    // create
    await db.dbSyncRecordStoreRef.record(syncRecord.id).delete(client);
    await stringMapStoreFactory
        .store(syncRecord.store.v)
        .record(syncRecord.key.v!)
        .delete(client);
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
    Timestamp? newLastTimestamp;
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
    dirtyRemoteSourceRecords = await readSource.getAllSourceRecordList(
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
    List<DbSyncRecord>? localSyncRecords;
    Map<SyncedRecordKey, DbSyncRecord>? localMap;

    if (fullSync) {
      localSyncRecords = await this.db.getSyncRecords();
      localMap = <SyncedRecordKey, DbSyncRecord>{};
      for (var syncRecord in localSyncRecords) {
        localMap[syncRecord.syncedKey] = syncRecord;
      }
    }

    /// Remote wins, unless the record is dirty locally (local wins then,
    /// the record is pushed up after the transaction).
    var conflictSyncRecordIds = <int>[];
    await this.db.syncTransaction((txn) async {
      // devPrint('count ${dirtyRemoteSourceRecords.length}');
      for (var remoteRecord in dirtyRemoteSourceRecords.list) {
        var remoteRecordData = remoteRecord.record.v;

        var store = remoteRecordData?.store.v;
        if (store == null ||
            remoteRecordData?.key.v == null ||
            remoteRecord.syncTimestamp.v == null ||
            remoteRecord.syncChangeId.v == null) {
          if (debugSyncedSync) {
            // ignore: avoid_print
            print('invalid dirty: $remoteRecord');
          }
          continue;
        } else if (!this.db.shouldSyncStore(store)) {
          continue;
        }

        /// Update last change id
        newLastChangeId = remoteRecord.syncChangeId.v!;
        newLastTimestamp = remoteRecord.syncTimestamp.v!;

        DbSyncRecord? local;
        var syncedKey = remoteRecord.syncedKey;

        if (fullSync) {
          local = localMap![syncedKey];
        } else {
          local = await this.db.getSyncRecord(
            db,
            stringMapStoreFactory.store(syncedKey.store).record(syncedKey.key),
          );
        }
        if (local == null) {
          if (!(remoteRecordData!.isDeleted)) {
            // create
            await _syncSourceRecordDown(txn, remoteRecord, stat);
          }
        } else {
          var localChangeNum = local.syncChangeId.v ?? 0;
          var remoteChangeNum = remoteRecord.syncChangeId.v!;
          if (remoteChangeNum > localChangeNum) {
            // The remote change num is strictly greater, remote wins,
            // even if the record is dirty locally (the local change is
            // discarded).
            await _syncSourceRecordDown(
              txn,
              remoteRecord,
              stat,
              existingSyncRecord: local,
            );
          } else if (local.isDirty) {
            // Same change num (or local above): the local change was made on
            // top of the latest remote version, local wins! Keep the local
            // data and push it up after the transaction.
            conflictSyncRecordIds.add(local.id);
          } else if (local.syncTimestamp.v != remoteRecord.syncTimestamp.v ||
              local.syncChangeId.v != remoteRecord.syncChangeId.v ||
              newSourceVersion) {
            // update
            await _syncSourceRecordDown(
              txn,
              remoteRecord,
              stat,
              existingSyncRecord: local,
            );
          } else {
            // Ok, in sync, nothing to do
          }
          localMap?.remove(syncedKey);
        }
      }
      // Clean up for full sync
      if (fullSync) {
        for (var localDbSync in localMap!.values) {
          if (localDbSync.isDirty) {
            // Dirty locally, local wins! Keep the local data and push it
            // up after the transaction.
            conflictSyncRecordIds.add(localDbSync.id);
            continue;
          }
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
    });

    /// Push up the locally dirty records for which local wins (they stay
    /// dirty for a read-only synchronizer).
    if (conflictSyncRecordIds.isNotEmpty && !isReadOnly) {
      var conflictDirtySourceRecords = await _getLocalDirtySourceRecordsByIds(
        conflictSyncRecordIds,
      );
      await _pushLocalDirtySourceRecords(conflictDirtySourceRecords, stat);
    }

    markFirstSyncDone();
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncDown: $stat');
    }
    return stat;
  }

  /// Wait for current sync to terminate
  @Deprecated('to remove')
  Future<void> lazyWaitSync() async {
    await waitSync();
  }
}
