import 'package:idb_shim/idb_client_logger.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart' as sync;
import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

mixin SyncedSdbMixin implements SyncedSdb {
  late final SdbFactory databaseFactory;

  /// Computed on open, actual store names synced
  @override
  late List<String> syncedStoreNames;

  /// True when first synchronization is done (even without data, i.e. last ChangeId should be zero)
  @override
  Future<void> initialSynchronizationDone() async {
    await onSyncMetaInfo().firstWhere((meta) => meta?.lastChangeId != null);
  }
}

var syncedSdbDebug = false; // devWarning(true);

var _buildersInitialized = false;

void cvInitSyncedDbBuilders() {
  if (!_buildersInitialized) {
    _buildersInitialized = true;

    cvAddConstructor(SdbSyncRecord.new);
    cvAddConstructor(SdbSyncMetaInfo.new);
  }
}

abstract class SyncedSdbBase with SyncedSdbMixin {
  final _syncMetaInfoSubject = BehaviorSubject<SdbSyncMetaInfo?>();
  final _syncDirtySubject = PublishSubject<bool>();
  final SyncedSdbOptions options;
  SyncedSdbBase({required this.options}) {
    cvInitSyncedDbBuilders();
  }

  @override
  final syncTransactionLock = Lock();

  /// Visible only for testing
  @override
  @visibleForTesting
  bool get trackChangesDisabled =>
      Zone.current[SyncedSdbExtension._zoneKey] == true;

  SdbDatabase? _database;

  Future<void> onChanges(
    SdbTransaction txn,
    List<SdbRecordChange<String, SdbModel>> changes,
  ) async {
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('onChanges: $changes');
    }
    await onChangesAny(txn, changes);
  }

  // Type unsafe assuming string, map
  Future<void> onChangesAny(
    SdbTransaction txn,
    List<SdbRecordChange> changes,
  ) async {
    if (trackChangesDisabled) return;
    for (var change in changes) {
      var changeRef = change.ref;
      if (syncedSdbDebug) {
        // ignore: avoid_print
        print('change: ${change.oldSnapshot} => ${change.newSnapshot}');
      }
      if (!trackChangesDisabled) {
        //if (change.isAdd) {
        // Need to read to handle put after delete
        var existingSyncRecord = await getSyncRecordAny(txn, changeRef);
        if (existingSyncRecord == null) {
          if (change.isDelete) {
            var record = syncRecordFromAny(changeRef)
              ..deleted.v = 1
              ..dirty.v = 1;
            if (syncedSdbDebug) {
              // ignore: avoid_print
              print('New dirty deleted record $record');
            }
            await sdbSyncRecordStoreRef.add(txn, record);
          } else {
            var record = syncRecordFromAny(changeRef)..dirty.v = 1;
            if (syncedSdbDebug) {
              // ignore: avoid_print
              print('New dirty record $record');
            }
            await sdbSyncRecordStoreRef.add(txn, record);
          }
        } else {
          if (change.isDelete) {
            if (existingSyncRecord.deleted.v != 1) {
              existingSyncRecord.dirty.v = 1;
              existingSyncRecord.deleted.v = 1;
              await existingSyncRecord.put(txn);
              if (syncedSdbDebug) {
                // ignore: avoid_print
                print('Mark dirty deleted record $existingSyncRecord');
              }
            }
          } else {
            // Mark dirty if needed
            if (existingSyncRecord.dirty.v != 1 ||
                existingSyncRecord.deleted.v == 1) {
              existingSyncRecord.dirty.v = 1;
              existingSyncRecord.deleted.clear();
              if (syncedSdbDebug) {
                // ignore: avoid_print
                print('Mark dirty existing sync record $existingSyncRecord');
              }
              await existingSyncRecord.put(txn);
            }
          }
        }
      }
    }
    _syncDirtySubject.add(true);
  }

  List<String> get _metaStoreNames => [
    sdbSyncRecordStoreRef.name,
    sdbSyncMetaStoreRef.name,
  ];
  @override
  Future<SdbDatabase> get database async =>
      _database ??= (await rawDatabase.then((db) {
        var extraStoreNames = _metaStoreNames;
        var systemStoreNames = syncedDbSystemStoreNames;
        var storeNames = <String>{};
        var optionsSyncedStoreNames = options.syncedStoreNames;
        var optionsSyncedExcludedStoreNames = options.syncedExcludedStoreNames;
        if (optionsSyncedStoreNames != null) {
          storeNames.addAll(optionsSyncedStoreNames);
        }
        if (optionsSyncedExcludedStoreNames != null) {
          storeNames.removeAll(optionsSyncedExcludedStoreNames);
        }
        storeNames.removeAll(systemStoreNames);
        syncedStoreNames = storeNames.toList();
        // Setup triggers
        for (var store in _syncStores) {
          store.addOnChangesListener(
            db,
            onChanges,
            extraStoreNames: extraStoreNames,
          );
        }
        if (_syncStores.isEmpty) {
          for (var store in _allStoresButMeta(db)) {
            store.addOnChangesListener(
              db,
              onChanges,
              extraStoreNames: extraStoreNames,
            );
          }
        }
        return db;
      }))!;

  @override
  late var scvSyncMetaInfoRef = sdbSyncMetaStoreRef.record('info');
  @override
  late var syncedDbSystemStoreNames = [
    sdbSyncRecordStoreRef.name,
    sdbSyncMetaStoreRef.name,
  ];

  /// Explicit sync stores
  List<SdbStoreRef<String, SdbModel>> get _syncStores =>
      syncedStoreNames.map((e) => SdbStoreRef<String, SdbModel>(e)).toList();

  var _closed = false;

  @override
  Future<void> close() async {
    _syncMetaInfoSubject.close().unawait();
    _syncDirtySubject.close().unawait();
    if (!_closed && _database != null) {
      _closed = true;
      await _database?.close();
    }
  }
}

/// Synced db
abstract class SyncedSdb implements SyncedDbCommon {
  /// Default name
  static String nameDefault = 'synced_sdb.db';

  // var dbSyncRecordStoreRef = cvIntStoreFactory.store<DbSyncRecord>('syncedR');
  // var dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>('syncedM');
  ScvStoreRef<int, SdbSyncRecord> get scvSyncRecordStoreRef;

  ScvStoreRef<String, SdbSyncMetaInfo> get scvSyncMetaStoreRef;

  ScvRecordRef<String, SdbSyncMetaInfo> get scvSyncMetaInfoRef;

  /// Computed on open, actual store names synced
  List<String> get syncedStoreNames;

  @protected
  Lock get syncTransactionLock;

  /// True when first synchronization is done (even without data, i.e. last ChangeId can be null but should be 0)
  Future<void> initialSynchronizationDone();

  /// Good for in memory manipulation of incomping data and unit test !
  factory SyncedSdb.newInMemory({required SyncedSdbOptions options}) =>
      _SyncedSdbInMemory(options: options);

  /// Constructor
  factory SyncedSdb({
    String? name,
    required SdbFactory databaseFactory,
    required SyncedSdbOptions options,
  }) => _SyncedSdbImpl(
    name: name,
    databaseFactory: databaseFactory,
    options: options,
  );

  factory SyncedSdb.fromOpenedDb({
    SdbDatabase? openedDatabase,
    required SyncedSdbOptions options,
  }) => _SyncedSdbImpl(options: options, openedDatabase: openedDatabase);

  static SyncedSdb openDatabase({
    String? name,
    required SdbFactory databaseFactory,
    List<String>? syncedExcludedStoreNames,
    List<String>? syncedStoreNames,
    required SyncedSdbOptions options,
  }) =>
      SyncedSdb(options: options, name: name, databaseFactory: databaseFactory);

  Future<SdbDatabase> get rawDatabase;

  Future<SdbDatabase> get database;

  List<String> get syncedDbSystemStoreNames;

  /// Visible only for testing
  @visibleForTesting
  bool get trackChangesDisabled;

  Future<void> close();
}

extension SyncedSdbExtension on SyncedSdb {
  SyncedSdbBase get _impl => this as _SyncedSdbImpl;

  /// Get dirty record
  Future<List<SdbSyncRecord>> txnGetDirtySyncRecords(SdbClient client) async {
    var dirtyRecords = await sdbSyncRecordDirtyIndexRef
        .record(1)
        .findObjects(client);
    //print('all records ${await sdbSyncRecordStoreRef.findRecords(client)}');
    //print('dirty records $dirtyRecords');
    return dirtyRecords;
  }

  Iterable<String> allStoreNamesButSynced(SdbDatabase db) {
    var storeNames = db.storeNames;
    return storeNames.where((name) => !(syncedStoreNames.contains(name)));
  }

  Iterable<SdbStoreRef<String, SdbModel>> _allStoresButMeta(SdbDatabase db) =>
      allStoreNamesButSynced(
        db,
      ).map((e) => SdbStoreRef<String, SdbModel>(e)).toList();

  /// Run in transaction.
  Future<T> transaction<T>({
    List<String>? storeNames,
    required FutureOr<T> Function(SdbTransaction transaction) run,
    SdbTransactionMode? mode,
  }) async {
    var db = await database;

    /// Run in transaction all stores!
    /// hopefully for a short period of time
    return db.inTransaction(
      storeNames: storeNames ?? db.storeNames.toList(),
      mode: mode,
      run: run,
    );
  }

  static const _zoneKey = #syncedSdbDisableChangeTracking;

  /// Disable change tracking during syncTransaction
  Future<T> syncTransaction<T>({
    List<String>? storeNames,
    SdbTransactionMode? mode,
    required FutureOr<T> Function(SdbTransaction transaction) run,
  }) async {
    return syncTransactionLock.synchronized(() async {
      return await runZoned(
        () => transaction(
          storeNames: storeNames,
          mode: mode,
          run: (txn) async {
            var result = await run(txn);
            return result;
          },
        ),
        zoneValues: {_zoneKey: true},
      );
    });
  }

  /// Raw access
  Future<void> txnPutSyncRecord(SdbClient? client, SdbSyncRecord record) async {
    client ??= await database;
    await record.put(client);
  }

  @visibleForTesting
  Future<void> clearSyncRecords(SdbClient? client) async {
    client ??= await database;
    await sdbSyncRecordStoreRef.delete(client);
  }

  @visibleForTesting
  Future<void> clearMetaInfo(SdbClient? client) async {
    client ??= await database;
    await scvSyncMetaInfoRef.delete(client);
  }

  @visibleForTesting
  Future<void> clearAllSyncInfo(SdbClient? client) async {
    await clearMetaInfo(client);
    await clearSyncRecords(client);
  }

  /// Get sync records
  Future<List<SdbSyncRecord>> getSyncRecords({SdbClient? client}) async {
    client ??= await database;
    return (await sdbSyncRecordStoreRef.findRecords(client)).toList();
  }

  Future<SdbSyncRecord?> getSyncRecord(
    SdbClient client,
    SdbRecordRef<String, Map<String, Object?>> record,
  ) {
    return sdbSyncRecordByStoreAndKeyIndexRef
        .record(record.store.name, record.key)
        .getObject(client);
  }

  Future<SdbSyncRecord?> getSyncRecordAny(
    SdbClient client,
    SdbRecordRef record,
  ) async {
    // !! very slow
    return await sdbSyncRecordStoreRef.findRecord(
      client,

      filter: SdbFilter.and([
        SdbFilter.equals(dbSyncRecordModel.store.k, record.store.name),
        SdbFilter.equals(dbSyncRecordModel.key.k, record.key),
      ]),
    );
  }

  Future<SdbSyncMetaInfo?> getSyncMetaInfo({SdbClient? client}) async {
    client ??= await database;
    var localMetaSyncInfo = await scvSyncMetaInfoRef.get(client);
    _impl._syncMetaInfoSubject.add(localMetaSyncInfo);
    return localMetaSyncInfo;
  }

  /// Last sync change id
  Future<int?> getSyncMetaInfoLastChangeId({SdbClient? client}) async {
    var metaInfo = await getSyncMetaInfo(client: client);
    return metaInfo?.lastChangeId.v;
  }

  /// Local sync meta info changes
  Stream<SdbSyncMetaInfo?> onSyncMetaInfo() async* {
    // ignore: unused_local_variable

    var subject = _impl._syncMetaInfoSubject;
    if (subject.valueOrNull == null) {
      database.then((db) async {
        /// getSyncMetaInfo will update the subject
        await getSyncMetaInfo(client: db);
      }).unawait();
    }
    yield* _impl._syncMetaInfoSubject.stream;
  }

  Stream<bool> onDirty() async* {
    // ignore: unused_local_variable
    var db = await database;
    yield* _impl._syncDirtySubject.stream;
  }

  /// Internal and test only.
  @protected
  Future<void> setSyncMetaInfo(
    SdbClient client,
    SdbSyncMetaInfo? dbSyncMetaInfo,
  ) async {
    if (dbSyncMetaInfo == null) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Deleting meta Info');
      }
      await scvSyncMetaInfoRef.delete(client);
    } else {
      if (!dbSyncMetaInfo.hasId) {
        dbSyncMetaInfo = scvSyncMetaInfoRef.cv()..copyFrom(dbSyncMetaInfo);
      }
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Setting meta Info $dbSyncMetaInfo');
      }
      await dbSyncMetaInfo.put(client);
      _impl._syncMetaInfoSubject.add(dbSyncMetaInfo);
    }
  }

  /// Ready to use
  Future<void> get ready => database;
}

/// New memory factory.
@doNotSubmit
SdbFactory newSdbFactoryMemoryLogger() =>
    // ignore: deprecated_member_use
    sdbFactoryFromIdb(newIdbFactoryMemory().debugWrapInLogger());

class _SyncedSdbInMemory extends _SyncedSdbImpl {
  static SdbFactory get inMemoryDatabaseFactory => newSdbFactoryMemory();

  //static DatabaseFactory get inMemoryDatabaseFactory => SqfliteLogget newDatabaseFactoryMemory();
  @visibleForTesting
  _SyncedSdbInMemory({required super.options})
    : super(databaseFactory: inMemoryDatabaseFactory);
}

class SyncedSdbOptions {
  final SdbDatabaseSchema schema;
  final int version;

  /// Synced store names, null means all
  final List<String>? syncedStoreNames;

  /// USed if synced store names is empty, to excluded some stores
  final List<String>? syncedExcludedStoreNames;

  SyncedSdbOptions({
    required this.schema,
    required this.version,
    this.syncedStoreNames,
    this.syncedExcludedStoreNames,
  });

  /// Copy with
  SyncedSdbOptions copyWith({
    SdbDatabaseSchema? schema,
    int? version,
    List<String>? syncedStoreNames,
    List<String>? syncedExcludedStoreNames,
  }) {
    return SyncedSdbOptions(
      schema: schema ?? this.schema,
      version: version ?? this.version,
      syncedStoreNames: syncedStoreNames ?? this.syncedStoreNames,
      syncedExcludedStoreNames:
          syncedExcludedStoreNames ?? this.syncedExcludedStoreNames,
    );
  }
}

final syncedSdbMetaSchema = SdbDatabaseSchema(
  stores: [
    sdbSyncMetaStoreRef.schema(),
    sdbSyncRecordStoreRef.schema(
      autoIncrement: true,
      indexes: [
        sdbSyncRecordBySyncIndexRef.schema(
          keyPath: dbSyncRecordModel.syncId.name,
        ),
        sdbSyncRecordByStoreAndKeyIndexRef.schema(
          keyPath: [dbSyncRecordModel.store.name, dbSyncRecordModel.key.name],
        ),
        sdbSyncRecordDirtyIndexRef.schema(
          keyPath: dbSyncRecordModel.dirty.name,
        ),
      ],
    ),
  ],
);

/// Default implementation
class _SyncedSdbImpl extends SyncedSdbBase implements SyncedSdb {
  String name;

  final SdbDatabase? openedDatabase;

  //static DatabaseFactory get inMemoryDatabaseFactory => SqfliteLogget newDatabaseFactoryMemory();
  @visibleForTesting
  _SyncedSdbImpl({
    SdbFactory? databaseFactory,
    this.openedDatabase,
    required SyncedSdbOptions options,
    @Deprecated('Use options.syncedStoreNames') List<String>? syncedStoreNames,
    @Deprecated('Use options.syncedStoreNames')
    List<String>? syncedExcludedStoreNames,
    String? name,
  }) : name = name ?? SyncedSdb.nameDefault,
       super(
         options: options.copyWith(
           syncedStoreNames: syncedStoreNames,
           syncedExcludedStoreNames: syncedExcludedStoreNames,
         ),
       ) {
    if (databaseFactory != null) {
      this.databaseFactory = databaseFactory;
    }
  }

  /*
  @override
  final dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>(
    'syncMeta',
  );
  @override
  final dbSyncRecordStoreRef = cvIntStoreFactory.store<DbSyncRecord>(
    'syncRecord',
  );*/

  @override
  late final rawDatabase = openedDatabase != null
      ? Future.value(openedDatabase)
      : databaseFactory.openDatabase(
          name,
          version: options.version,
          schema: options.schema,
        );

  @override
  ScvStoreRef<String, SdbSyncMetaInfo> get scvSyncMetaStoreRef =>
      sync.sdbSyncMetaStoreRef;

  @override
  ScvStoreRef<int, SdbSyncRecord> get scvSyncRecordStoreRef =>
      sync.sdbSyncRecordStoreRef;
}

/// Sync record store ref
//typedef ScvSyncRecordStoreRef = ScvStringStoreRef<SdbSyncRecord>;

// /// Record ref
// typedef SyncedDbRecordRef = RecordRef<String, Model>;
typedef SyncedSdbRecordRef = SdbRecordRef<String, SdbModel>;
SdbSyncRecord syncRecordFrom(SyncedSdbRecordRef record) {
  return SdbSyncRecord()
    ..key.v = record.key
    ..store.v = record.store.name;
}

SdbSyncRecord syncRecordFromAny(SdbRecordRef record) {
  return SdbSyncRecord()
    ..key.v = record.key as String
    ..store.v = record.store.name;
}
