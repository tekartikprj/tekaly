import 'dart:math';

import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_common_utils/single_flight.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/list_utils.dart';
import 'package:tekartik_common_utils/stream/stream_join.dart';

import 'model/db_sync_record.dart';
import 'model/source_meta_info.dart';
import 'model/source_record.dart';
import 'synced_db.dart';
import 'synced_source.dart';

var _debugSyncedSync = false;

/// Debug Synced sync
bool get debugSyncedSync => _debugSyncedSync;

@Deprecated('Debug Synced sync')
set debugSyncedSync(bool debugSyncedSync) => _debugSyncedSync = debugSyncedSync;

@doNotSubmit
set debugSyncedDbSynchronizer(bool debugSyncedSync) =>
    _debugSyncedSync = debugSyncedSync;

/// Synced sync stat
class SyncedSyncStat {
  /// Local created count
  int localCreatedCount;

  /// Remote updated count
  int remoteUpdatedCount;

  /// Local updated count
  int localUpdatedCount;

  /// Remote updated count
  int remoteCreatedCount;

  /// Remote deleted count
  int remoteDeletedCount;

  /// Local deleted count
  int localDeletedCount;

  /// No action done
  final bool notExecuted;

  /// Default constructor
  SyncedSyncStat({
    this.notExecuted = false,

    this.localCreatedCount = 0,
    this.localUpdatedCount = 0,
    this.localDeletedCount = 0,
    this.remoteCreatedCount = 0,
    this.remoteUpdatedCount = 0,
    this.remoteDeletedCount = 0,
  });

  @override
  int get hashCode =>
      localUpdatedCount +
      localDeletedCount +
      localCreatedCount +
      remoteUpdatedCount +
      remoteDeletedCount +
      remoteCreatedCount;

  /// Modify this
  void add(SyncedSyncStat other) {
    localCreatedCount += other.localCreatedCount;
    localUpdatedCount += other.localUpdatedCount;
    localDeletedCount += other.localDeletedCount;
    remoteCreatedCount += other.remoteCreatedCount;
    remoteUpdatedCount += other.remoteUpdatedCount;
    remoteDeletedCount += other.remoteDeletedCount;
  }

  @override
  bool operator ==(Object other) {
    if (other is SyncedSyncStat) {
      if (other.localCreatedCount != localCreatedCount) {
        return false;
      }
      if (other.remoteCreatedCount != remoteCreatedCount) {
        return false;
      }

      if (other.localUpdatedCount != localUpdatedCount) {
        return false;
      }
      if (other.remoteUpdatedCount != remoteUpdatedCount) {
        return false;
      }
      if (other.remoteDeletedCount != remoteDeletedCount) {
        return false;
      }
      if (other.localDeletedCount != localDeletedCount) {
        return false;
      }
      return true;
    }
    return super == other;
  }

  @override
  String toString() {
    var map = asModel({
      if (localCreatedCount > 0) 'localCreatedCount': localCreatedCount,
      if (localUpdatedCount > 0) 'localUpdatedCount': localUpdatedCount,
      if (localDeletedCount > 0) 'localDeletedCount': localDeletedCount,
      if (remoteCreatedCount > 0) 'remoteCreatedCount': remoteCreatedCount,
      if (remoteUpdatedCount > 0) 'remoteUpdatedCount': remoteUpdatedCount,
      if (remoteDeletedCount > 0) 'remoteDeletedCount': remoteDeletedCount,
    });
    return 'SyncedSyncStat($map)';
  }
}

/// Synced sync source record
class SyncedSyncSourceRecord extends SyncedSyncSourceRecordCommon {
  /// Set sync record
  set syncRecord(DbSyncRecord? value) {
    syncRecordCommon = value;
  }

  /// Get sync record
  DbSyncRecord? get syncRecord => syncRecordCommon as DbSyncRecord?;
}

/// Synced sync source record
class SyncedSyncSourceRecordCommon {
  /// Source record
  CvSyncedSourceRecord? sourceRecord;

  /// Sync record common
  DbSyncRecordCommon? syncRecordCommon;

  /// Has sync id
  bool get hasSyncId => syncRecordCommon?.syncId.v != null;

  /// Is new local record
  bool get isNewLocalRecord => !hasSyncId;
}

/// Compat
typedef SyncedDbSourceSync = SyncedDbSynchronizer;

/// Synced db synchronized
class SyncedDbSynchronizer extends SyncedDbSynchronizerCommon {
  /// The database being synchronized
  late final SyncedDb db = dbCommon as SyncedDb;

  final _firstSyncDoneCompleter = Completer<void>.sync();

  /// True when the first sync is done (could take forever the first time if offline)
  Future<void> firstSyncDownDone() => _firstSyncDoneCompleter.future;

  /// Get local dirty source records
  Future<List<SyncedSyncSourceRecord>> getLocalDirtySourceRecords() async {
    var list = <SyncedSyncSourceRecord>[];
    await db.syncTransaction((txn) async {
      var dirtySyncRecords = await db.txnGetDirtySyncRecords(txn);
      for (var dirtySyncRecord in dirtySyncRecords) {
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
        list.add(
          SyncedSyncSourceRecord()
            ..sourceRecord = sourceRecord
            ..syncRecord = dirtySyncRecord,
        );
      }
    });
    return list;
  }

  // Auto sync subscription
  StreamSubscription? _autoSyncSourceSubscription;
  StreamSubscription? _autoSyncDbSubscription;

  /// Synchronizer
  SyncedDbSynchronizer({
    required SyncedDb db,
    required super.source,
    super.autoSync = false,
  }) : super(db: db) {
    if (autoSync) {
      _autoSyncSourceSubscription =
          streamJoin2(source.onMetaInfo(), db.onSyncMetaInfo()).listen((event) {
            var remote = event.$1;
            var local = event.$2;
            var remoteLastChangeId = remote?.lastChangeId.v ?? 0;
            var localLastChangeId = local?.lastChangeId.v ?? 0;
            // devPrint('remote $remote, local: $local');
            if (remoteLastChangeId != localLastChangeId) {
              lazySync();
            } else if (remoteLastChangeId == 0 && localLastChangeId == 0) {
              lazySync();
            }
          });
      _autoSyncDbSubscription = db.onDirty().listen((dirty) {
        // devPrint('localDirty $dirty');
        if (dirty) {
          lazySync();
        }
      });
    }
  }

  // ignore: unused_field
  var _closing = false;

  /// Needed for autoSync.
  /// Wait for last sync to terminate.
  Future<void> close() async {
    _autoSyncSourceSubscription?.cancel().unawait();
    _autoSyncDbSubscription?.cancel().unawait();
    await syncLock.synchronized(() {
      _closing = true;
    });
    try {
      await _singleFlight.close();
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

    var dirtySourceRecords = await getLocalDirtySourceRecords();
    if (dirtySourceRecords.isNotEmpty) {
      for (var chunk in listChunk(dirtySourceRecords, stepLimitUp ?? 10)) {
        /// Multiple items at once locally
        var list = <SyncedSyncSourceRecord>[];
        for (var syncSourceRecord in chunk) {
          list.add(
            SyncedSyncSourceRecord()
              ..sourceRecord = await source.putSourceRecord(
                syncSourceRecord.sourceRecord!,
              )
              ..syncRecord = syncSourceRecord.syncRecord,
          );
        }

        await db.syncTransaction((txn) async {
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
        });
      }
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncUp: $stat');
    }
    return stat;
  }

  Future<void> _syncSourceRecordDown(
    DatabaseClient client,
    CvSyncedSourceRecord remoteRecord,
    SyncedSyncStat stat,
  ) async {
    await db.dbSyncRecordStoreRef.add(
      client,
      (DbSyncRecord()
        ..syncId.v = remoteRecord.syncId.v
        ..syncTimestamp.v = remoteRecord.syncTimestamp.v
        ..store.v = remoteRecord.record.v!.store.v
        ..key.v = remoteRecord.record.v!.key.v
        ..deleted.v = remoteRecord.record.v!.deleted.v),
    );

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
    List<DbSyncRecord>? localSyncRecords;
    Map<SyncedRecordKey, DbSyncRecord>? localMap;

    if (fullSync) {
      localSyncRecords = await this.db.getSyncRecords();
      localMap = <SyncedRecordKey, DbSyncRecord>{};
      for (var syncRecord in localSyncRecords) {
        localMap[syncRecord.syncedKey] = syncRecord;
      }
    }

    /// Remote wins!
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
    });

    if (!_firstSyncDoneCompleter.isCompleted) {
      _firstSyncDoneCompleter.complete();
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('syncDown: $stat');
    }
    return stat;
  }

  /// Wait for current sync to terminate
  @Deprecated('to remove')
  Future<void> lazyWaitSync() async {
    await _singleFlight.wait();
  }
}

/// Synced db synchronized
abstract class SyncedDbSynchronizerCommon {
  /// Sync subject
  final _onSyncedSubject = StreamController<SyncedSyncStat>.broadcast();

  /// On synced stream
  Stream<SyncedSyncStat> onSynced() => _onSyncedSubject.stream;

  /// The source being synchronized
  final SyncedSource source;

  /// Default to 10 up
  int? stepLimitUp;

  /// Default to 100 down
  int? stepLimitDown;

  /// Sync lock
  final syncLock = Lock();

  /// Constructor
  SyncedDbSynchronizerCommon({
    required this.source,
    this.autoSync = false,
    required SyncedDbCommon db,
  }) : dbCommon = db;

  /// Db common
  final SyncedDbCommon dbCommon;

  /// Auto sync
  final bool autoSync;

  /// Sync down
  Future<SyncedSyncStat> doSyncDown();

  /// Sync down
  Future<SyncedSyncStat> syncDown() async {
    return syncLock.synchronized(() {
      return doSyncDown();
    });
  }

  /// Sync up
  Future<SyncedSyncStat> doSyncUp({bool fullSync = false});

  /// Sync dirty records up
  Future<SyncedSyncStat> syncUp({bool fullSync = false}) async {
    return syncLock.synchronized(() {
      return doSyncUp(fullSync: fullSync);
    });
  }

  /// Sync up and down
  Future<SyncedSyncStat> doSync() async {
    var stat = SyncedSyncStat();
    var upStat = await doSyncUp();
    stat.add(upStat);
    var downStat = await doSyncDown();
    stat.add(downStat);
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('_end sync $stat');
    }
    _onSyncedSubject.add(stat);
    return stat;
  }

  late final _singleFlight = SingleFlight<SyncedSyncStat>(() async {
    return await syncLock.synchronized(() async {
      try {
        return await doSync();
      } catch (e, st) {
        if (debugSyncedSync) {
          // ignore: avoid_print
          print('sync error $e $st');
        }
        rethrow;
      }
    });
  });

  /// Sync up and down
  FutureOr<SyncedSyncStat> sync() {
    return _singleFlight.run();
  }

  CvMetaInfo? _lastSyncMetaInfo;

  /// Last source meta info
  CvMetaInfo? get lastSyncMetaInfo => _lastSyncMetaInfo;

  /// Use it internally to cache the source meta info.
  Future<CvMetaInfo?> getSourceMetaInfo() async {
    var sourceMetaInfo = await source.getMetaInfo();
    _lastSyncMetaInfo = sourceMetaInfo;
    return lastSyncMetaInfo;
  }

  /// Closing
  void dispose() {
    _onSyncedSubject.close();
  }
}
