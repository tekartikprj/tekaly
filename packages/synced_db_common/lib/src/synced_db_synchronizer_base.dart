import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cv/cv.dart';
import 'package:meta/meta.dart';
import 'package:tekartik_common_utils/future_utils.dart';
import 'package:tekartik_common_utils/list_utils.dart';
import 'package:tekartik_common_utils/stream/stream_join.dart';

import 'model/db_sync_common.dart';
import 'model/source_record.dart';
import 'synced_db_common_types.dart';
import 'synced_db_synchronizer_common.dart';
import 'synced_source.dart';

/// Synchronizer holding the sync up and down algorithm, shared by the sembast
/// and sdb implementations which only give access to their local database
/// through the `local...` methods.
///
/// [TClient] is the local database client (transaction) type, [TSyncRecord]
/// the local sync record type and [TSyncSourceRecord] the type pairing a
/// source record with its local sync record.
///
/// Record values given to and returned by the `local...` methods are in the
/// synced db format (the one of the source), the implementation converting
/// them if its local database uses another one.
abstract class SyncedDbSynchronizerBase<
  TClient,
  TSyncRecord extends DbSyncRecordCommon,
  TSyncSourceRecord extends SyncedSyncSourceRecordCommon
>
    extends SyncedDbSynchronizerCommon {
  // Auto sync subscription
  StreamSubscription? _autoSyncSourceSubscription;
  StreamSubscription? _autoSyncDbSubscription;

  // Sync status subscriptions
  StreamSubscription? _statusMetaInfoSubscription;
  StreamSubscription? _statusDirtySubscription;

  /// Constructor, see [SyncedDbSynchronizerCommon].
  ///
  /// In [autoSync] mode, a synchronization is triggered when the source and
  /// local meta info differ and when the local database gets dirty.
  SyncedDbSynchronizerBase({
    required super.db,
    super.source,
    super.readSource,
    super.writeSource,
    super.autoSync = false,
    super.retryOptions,
  }) {
    if (autoSync) {
      _autoSyncSourceSubscription =
          streamJoin2(
            // An unreachable source reports an error rather than its meta
            // info: it must start the retries, it never reaches the join.
            readSource.onMetaInfo().handleError(handleAutoSyncSourceError),
            localOnSyncMetaInfo(),
          ).listen((event) {
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
        _autoSyncDbSubscription = localOnDirty().listen((dirty) {
          if (dirty) {
            triggerAutoSync();
          }
        });
      }
      // The joined meta info stream above only emits once the source has
      // reported its meta info, which never happens while the source is
      // unreachable: make sure a first synchronization is attempted anyway.
      startFirstSyncWatchdog();
      ensureSyncStatusTracking();
    }
  }

  @override
  FutureOr<SyncedSyncStat> autoSyncAction() => lazySync();

  /// Stop listening to the source and local changes, called by the
  /// implementations `close`.
  @protected
  void cancelAutoSync() {
    _autoSyncSourceSubscription?.cancel().unawait();
    _autoSyncDbSubscription?.cancel().unawait();
    _statusMetaInfoSubscription?.cancel().unawait();
    _statusDirtySubscription?.cancel().unawait();
  }

  @override
  void startSyncStatusTracking() {
    void onError(Object error) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('sync status tracking error: $error');
      }
    }

    _statusMetaInfoSubscription = localOnSyncMetaInfo().listen(
      (metaInfo) =>
          updateLocalSyncState(synced: metaInfo?.lastChangeId.v != null),
      onError: onError,
    );
    if (!isReadOnly) {
      _statusDirtySubscription = localOnDirty().listen(
        (dirty) => updateLocalSyncState(hasLocalChanges: dirty),
        onError: onError,
      );
      refreshLocalSyncState().catchError(onError).unawait();
    }
  }

  @override
  Future<void> refreshLocalSyncState() async {
    if (isReadOnly) {
      return;
    }
    updateLocalSyncState(hasLocalChanges: await localHasDirtySyncRecords());
  }

  /// Run [action] in a local transaction, change tracking disabled (the
  /// changes made by the synchronization do not make the records dirty).
  @protected
  Future<T> localSyncTransaction<T>(Future<T> Function(TClient txn) action);

  /// The locally dirty sync records.
  @protected
  Future<List<TSyncRecord>> localGetDirtySyncRecords(TClient txn);

  /// True when some local sync records are dirty (outside a transaction).
  @protected
  Future<bool> localHasDirtySyncRecords();

  /// All the local sync records.
  @protected
  Future<List<TSyncRecord>> localGetSyncRecords();

  /// The local sync record [id].
  @protected
  Future<TSyncRecord?> localGetSyncRecordById(TClient client, int id);

  /// The local sync record of the record [key].
  @protected
  Future<TSyncRecord?> localGetSyncRecordByKey(
    TClient client,
    SyncedRecordKey key,
  );

  /// The id of a local sync [record].
  @protected
  int localSyncRecordId(TSyncRecord record);

  /// A new local sync record, bound to the existing one [id] if set.
  @protected
  TSyncRecord localNewSyncRecord([int? id]);

  /// Set the deleted flag of a local sync [record].
  @protected
  void localSetSyncRecordDeleted(TSyncRecord record, bool? deleted);

  /// Set the dirty flag of a local sync [record].
  @protected
  void localSetSyncRecordDirty(TSyncRecord record, bool dirty);

  /// Add a new local sync [record].
  @protected
  Future<void> localAddSyncRecord(TClient client, TSyncRecord record);

  /// Put an existing local sync [record].
  @protected
  Future<void> localPutSyncRecord(TClient client, TSyncRecord record);

  /// Delete the local sync record [id].
  @protected
  Future<void> localDeleteSyncRecord(TClient client, int id);

  /// The local value (synced db format) of the record [key], null if absent.
  @protected
  Future<Model?> localGetRecordValue(TClient client, SyncedRecordKey key);

  /// True if the record [key] exists locally.
  @protected
  Future<bool> localRecordExists(TClient client, SyncedRecordKey key);

  /// Put the [value] (synced db format) of the record [key] locally.
  @protected
  Future<void> localPutRecordValue(
    TClient client,
    SyncedRecordKey key,
    Model value,
  );

  /// Delete the record [key] locally.
  @protected
  Future<void> localDeleteRecord(TClient client, SyncedRecordKey key);

  /// The local sync meta info.
  @protected
  Future<DbSyncMetaInfoCommon?> localGetSyncMetaInfo();

  /// Save the local sync meta info.
  @protected
  Future<void> localSetSyncMetaInfo(
    TClient txn, {
    required int lastChangeId,
    required SyncedDbTimestamp? lastTimestamp,
    required int? sourceVersion,
  });

  /// Local sync meta info changes.
  @protected
  Stream<DbSyncMetaInfoCommon?> localOnSyncMetaInfo();

  /// Local dirty state changes.
  @protected
  Stream<bool> localOnDirty();

  /// True if the records of [store] coming from the source are synchronized
  /// locally, all by default.
  @protected
  bool localShouldSyncStore(String store) => true;

  /// A new source record / local sync record pair.
  @protected
  TSyncSourceRecord newSyncSourceRecord();

  TSyncSourceRecord _newSyncSourceRecord(
    CvSyncedSourceRecord sourceRecord,
    TSyncRecord? syncRecord,
  ) => newSyncSourceRecord()
    ..sourceRecord = sourceRecord
    ..syncRecordCommon = syncRecord;

  TSyncRecord _syncRecordOf(TSyncSourceRecord syncSourceRecord) =>
      syncSourceRecord.syncRecordCommon! as TSyncRecord;

  /// Get local dirty source records
  Future<List<TSyncSourceRecord>> getLocalDirtySourceRecords() async {
    var list = <TSyncSourceRecord>[];
    await localSyncTransaction((txn) async {
      var dirtySyncRecords = await localGetDirtySyncRecords(txn);
      for (var dirtySyncRecord in dirtySyncRecords) {
        list.add(await _txnGetDirtySyncSourceRecord(txn, dirtySyncRecord));
      }
    });
    return list;
  }

  /// Reload the source records to push for the given sync record ids,
  /// skipping the ones no longer dirty.
  Future<List<TSyncSourceRecord>> _getLocalDirtySourceRecordsByIds(
    Iterable<int> syncRecordIds,
  ) async {
    var list = <TSyncSourceRecord>[];
    await localSyncTransaction((txn) async {
      for (var id in syncRecordIds) {
        var syncRecord = await localGetSyncRecordById(txn, id);
        if (syncRecord == null || !syncRecord.isDirty) {
          continue;
        }
        list.add(await _txnGetDirtySyncSourceRecord(txn, syncRecord));
      }
    });
    return list;
  }

  /// Build the source record to push for a dirty sync record.
  Future<TSyncSourceRecord> _txnGetDirtySyncSourceRecord(
    TClient txn,
    TSyncRecord dirtySyncRecord,
  ) async {
    // Try to get event if deleted
    var syncedKey = dirtySyncRecord.syncedKey;
    var value = await localGetRecordValue(txn, syncedKey);
    // Check and fix deleted
    if (dirtySyncRecord.isDeleted) {
      if (value != null) {
        if (debugSyncedSync) {
          // ignore: avoid_print
          print(
            'Found a record. Weird, deleted flag set for $syncedKey - deleting record',
          );
        }
        await localDeleteRecord(txn, syncedKey);
        value = null;
      } else {
        // Ok
      }
    } else {
      if (value == null) {
        if (debugSyncedSync) {
          // ignore: avoid_print
          print(
            'Cannot find modified record. Weird, missing the deleted flag for $syncedKey - setting the deleted flag',
          );
        }
        // important to set for later
        localSetSyncRecordDeleted(dirtySyncRecord, true);
        await localPutSyncRecord(txn, dirtySyncRecord);
      } else {
        // ok
      }
    }

    var sourceRecord = CvSyncedSourceRecord()
      //..syncTimestamp.v = dirtySyncRecord.syncTimestamp.v
      ..syncId.v = dirtySyncRecord.syncId.v
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = dirtySyncRecord.store.v
        ..key.v = dirtySyncRecord.key.v
        ..deleted.v = dirtySyncRecord.isDeleted
        ..value.v = value);
    return _newSyncSourceRecord(sourceRecord, dirtySyncRecord);
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
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('syncUp: found ${dirtySourceRecords.length} dirty records');
      }
      await _pushLocalDirtySourceRecords(dirtySourceRecords, stat);
    } else {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('syncUp: no dirty records');
      }
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncUp: $stat');
    }
    return stat;
  }

  /// Push local dirty source records up, updating [stat].
  Future<void> _pushLocalDirtySourceRecords(
    List<TSyncSourceRecord> dirtySourceRecords,
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
        var sentList = <TSyncSourceRecord>[];

        /// Put responses, one per sent record
        var list = <TSyncSourceRecord>[];

        /// Remote records winning over the local dirty change (their change
        /// num is strictly greater), to apply locally instead of pushing.
        var remoteWinList = <TSyncSourceRecord>[];
        for (var syncSourceRecord in chunk) {
          var syncRecord = _syncRecordOf(syncSourceRecord);

          /// Remote wins if the remote change num is strictly greater than
          /// the last change num seen locally: read the remote record first.
          var localChangeNum = syncRecord.syncChangeId.v ?? 0;
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
            remoteWinList.add(_newSyncSourceRecord(remoteRecord, syncRecord));
            continue;
          }
          sentList.add(syncSourceRecord);
          list.add(
            _newSyncSourceRecord(
              await writeSource.putSourceRecord(syncSourceRecord.sourceRecord!),
              syncRecord,
            ),
          );
        }

        await localSyncTransaction((txn) async {
          /// Apply the remote records winning over the local dirty change
          /// (the local change is discarded, the dirty flag cleared).
          for (var remoteWin in remoteWinList) {
            await _syncSourceRecordDown(
              txn,
              remoteWin.sourceRecord!,
              stat,
              existingSyncRecord: _syncRecordOf(remoteWin),
            );
          }
          for (var i = 0; i < list.length; i++) {
            var syncSourceRecord = list[i];

            /// The record data that was sent to the source
            var sentRecordData = sentList[i].sourceRecord!.record.v!;
            var isNew = syncSourceRecord.isNewLocalRecord;
            var responseRecord = syncSourceRecord.sourceRecord!;
            var originalSyncRecord = _syncRecordOf(syncSourceRecord);
            var newSyncRecord =
                localNewSyncRecord(localSyncRecordId(originalSyncRecord))
                  ..store.v = responseRecord.record.v!.store.v
                  ..key.v = responseRecord.record.v!.key.v
                  ..syncId.v = responseRecord.syncId.v
                  // id from the original syncRecord
                  //..id = originalSyncRecord.id
                  ..syncTimestamp.v = responseRecord.syncTimestamp.v
                  ..syncChangeId.v = responseRecord.syncChangeId.v;
            localSetSyncRecordDeleted(
              newSyncRecord,
              responseRecord.record.v!.deleted.v,
            );
            localSetSyncRecordDirty(newSyncRecord, false);
            var syncedKey = newSyncRecord.syncedKey;

            /// Check whether another local change happened during
            /// putSourceRecord, i.e. the current local data no longer
            /// matches what was sent.
            var currentValue = await localGetRecordValue(txn, syncedKey);
            bool changedDuringPut;
            if (sentRecordData.deleted.v ?? false) {
              changedDuringPut = currentValue != null;
            } else {
              changedDuringPut =
                  currentValue == null ||
                  !const DeepCollectionEquality().equals(
                    currentValue,
                    sentRecordData.value.v,
                  );
            }
            if (changedDuringPut) {
              // Keep the record dirty and the local data untouched, only
              // save the sync info from the response so that the next
              // push updates the same source record.
              var currentSyncRecord = await localGetSyncRecordById(
                txn,
                localSyncRecordId(originalSyncRecord),
              );
              if (currentSyncRecord == null) {
                currentSyncRecord = newSyncRecord;
                localSetSyncRecordDeleted(
                  currentSyncRecord,
                  currentValue == null,
                );
              }
              localSetSyncRecordDirty(currentSyncRecord, true);
              currentSyncRecord
                ..syncId.v = responseRecord.syncId.v
                ..syncTimestamp.v = responseRecord.syncTimestamp.v
                ..syncChangeId.v = responseRecord.syncChangeId.v;
              if (debugSyncedSync) {
                // ignore: avoid_print
                print(
                  'syncUp: record changed during push, will push again $currentSyncRecord',
                );
              }
              await localPutSyncRecord(txn, currentSyncRecord);
              changedSyncRecordIds.add(localSyncRecordId(originalSyncRecord));
              if ((newSyncRecord.isDeleted) ||
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
            if (debugSyncedSync) {
              // ignore: avoid_print
              print(
                'syncUp: putting sync record ${newSyncRecord.store.v} - ${newSyncRecord.key.v} : $newSyncRecord',
              );
            }
            await localPutSyncRecord(txn, newSyncRecord);

            /// Handle deleted case too. (!warning that could delete data at some point)
            if ((newSyncRecord.isDeleted) ||
                (responseRecord.record.v!.value.isNull)) {
              stat.remoteDeletedCount++;
              await localDeleteRecord(txn, syncedKey);
            } else {
              if (isNew) {
                stat.remoteCreatedCount++;
              } else {
                stat.remoteUpdatedCount++;
              }
              var data = asModel(responseRecord.record.v!.value.v ?? {});
              if (debugSyncedSync) {
                // ignore: avoid_print
                print('syncUp: putting data record $syncedKey : $data');
              }
              await localPutRecordValue(txn, syncedKey, data);
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

  /// Sync dirty records up
  @override
  Future<SyncedSyncStat> doSyncDown() async {
    var stat = SyncedSyncStat();

    var localMetaSyncInfo = await localGetSyncMetaInfo();
    var hasInitialLastChangeId = localMetaSyncInfo?.lastChangeId.v != null;
    var initialLastChangeIdOrNull = localMetaSyncInfo?.lastChangeId.v;
    var initialLastChangeId = initialLastChangeIdOrNull ?? -1;
    var fullSync = initialLastChangeId == -1;

    var newLastChangeId = initialLastChangeIdOrNull ?? 0;
    SyncedDbTimestamp? newLastTimestamp;
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
    Map<SyncedRecordKey, TSyncRecord>? localMap;

    if (fullSync) {
      localMap = <SyncedRecordKey, TSyncRecord>{};
      for (var syncRecord in await localGetSyncRecords()) {
        localMap[syncRecord.syncedKey] = syncRecord;
      }
    }

    /// Remote wins, unless the record is dirty locally (local wins then,
    /// the record is pushed up after the transaction).
    var conflictSyncRecordIds = <int>[];
    await localSyncTransaction((txn) async {
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
        } else if (!localShouldSyncStore(store)) {
          continue;
        }

        /// Update last change id
        newLastChangeId = remoteRecord.syncChangeId.v!;
        newLastTimestamp = remoteRecord.syncTimestamp.v!;

        TSyncRecord? local;
        var syncedKey = remoteRecord.syncedKey;

        if (fullSync) {
          local = localMap![syncedKey];
        } else {
          local = await localGetSyncRecordByKey(txn, syncedKey);
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
            // Same change num (or local above): the local change was made
            // on top of the latest remote version, local wins! Keep the
            // local data and push it up after the transaction.
            conflictSyncRecordIds.add(localSyncRecordId(local));
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
            conflictSyncRecordIds.add(localSyncRecordId(localDbSync));
            continue;
          }
          if (debugSyncedSync) {
            // ignore: avoid_print
            print('deleting: $localDbSync');
          }
          await localDeleteSyncRecord(txn, localSyncRecordId(localDbSync));
          await localDeleteRecord(txn, localDbSync.syncedKey);
          stat.localDeletedCount++;
        }
      }

      // Use meta if available
      if (dirtyRemoteSourceRecords.lastChangeId != null) {
        newLastChangeId = dirtyRemoteSourceRecords.lastChangeId!;
      }
      // An empty list does not move the cursor to the source meta last change
      // id: a client answering from its cache (offline) returns an empty list,
      // the records it never received would then be skipped for good. The
      // next sync reads again from the current cursor, which is cheap.
      Future<void> saveMetaInfo() async {
        await localSetSyncMetaInfo(
          txn,
          lastChangeId: newLastChangeId,
          lastTimestamp: newLastTimestamp,
          sourceVersion: initialSourceMeta?.version.v,
        );
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

    // The data is synchronized down, even if pushing the conflicts fails.
    markFirstSyncDone();

    /// Push up the locally dirty records for which local wins (they stay
    /// dirty for a read-only synchronizer).
    if (conflictSyncRecordIds.isNotEmpty && !isReadOnly) {
      var conflictDirtySourceRecords = await _getLocalDirtySourceRecordsByIds(
        conflictSyncRecordIds,
      );
      await _pushLocalDirtySourceRecords(conflictDirtySourceRecords, stat);
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncDown: $stat');
    }

    return stat;
  }

  Future<void> _syncSourceRecordDown(
    TClient client,
    CvSyncedSourceRecord remoteRecord,
    SyncedSyncStat stat, {
    TSyncRecord? existingSyncRecord,
  }) async {
    var remoteRecordData = remoteRecord.record.v!;
    var syncRecord =
        localNewSyncRecord(
            existingSyncRecord == null
                ? null
                : localSyncRecordId(existingSyncRecord),
          )
          ..syncId.v = remoteRecord.syncId.v
          ..syncTimestamp.v = remoteRecord.syncTimestamp.v
          ..syncChangeId.v = remoteRecord.syncChangeId.v
          ..store.v = remoteRecordData.store.v
          ..key.v = remoteRecordData.key.v;
    localSetSyncRecordDeleted(syncRecord, remoteRecordData.deleted.v ?? false);
    if (existingSyncRecord == null) {
      await localAddSyncRecord(client, syncRecord);
    } else {
      // Overwrite the existing sync record, clearing the dirty flag
      // (remote wins).
      localSetSyncRecordDirty(syncRecord, false);
      await localPutSyncRecord(client, syncRecord);
    }

    var syncedKey = remoteRecord.syncedKey;
    if (remoteRecord.isDeleted) {
      stat.localDeletedCount++;
      await localDeleteRecord(client, syncedKey);
    } else {
      if (await localRecordExists(client, syncedKey)) {
        stat.localUpdatedCount++;
      } else {
        stat.localCreatedCount++;
      }
      try {
        await localPutRecordValue(client, syncedKey, remoteRecordData.value.v!);
      } catch (e, st) {
        if (debugSyncedSync) {
          // ignore: avoid_print
          print('Error putting record $syncedKey: $e');
          // ignore: avoid_print
          print(st);
        }
        rethrow;
      }
    }
  }
}
