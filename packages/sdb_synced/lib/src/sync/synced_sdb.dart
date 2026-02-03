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
  final SyncedSdbOptions options;
  SyncedSdbBase({required this.options}) {
    cvInitSyncedDbBuilders();
  }

  @override
  final syncTransactionLock = Lock();

  /// Visible only for testing
  @override
  @visibleForTesting
  var trackChangesDisabled = false;

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
    for (var change in changes) {
      var changeRef = change.ref;
      if (syncedSdbDebug) {
        // ignore: avoid_print
        print(
          'change: ${change.oldSnapshot} => ${change.newSnapshot} $trackChangesDisabled',
        );
      }
      if (!trackChangesDisabled) {
        //if (change.isAdd) {
        // Need to read to handle put after delete
        var existingSyncRecord = await getSyncRecordAny(txn, changeRef);
        if (existingSyncRecord == null) {
          if (change.isDelete) {
            await dbSyncRecordStoreRef.add(
              txn,
              (syncRecordFromAny(changeRef)
                ..dirty.v = true
                ..deleted.v = true),
            );
          } else {
            await dbSyncRecordStoreRef.add(
              txn,
              (syncRecordFromAny(changeRef)..dirty.v = true),
            );
          }
        } else {
          if (change.isDelete) {
            if (existingSyncRecord.deleted.v != true) {
              existingSyncRecord.dirty.v = true;
              existingSyncRecord.deleted.v = true;
              await existingSyncRecord.put(txn);
            }
          } else {
            // Mark dirty if needed
            if (existingSyncRecord.dirty.v != true ||
                existingSyncRecord.deleted.v == true) {
              existingSyncRecord.dirty.v = true;
              existingSyncRecord.deleted.clear();
              await existingSyncRecord.put(txn);
            }
          }
        }
      }
    }
  }

  List<String> get _metaStoreNames => [
    dbSyncRecordStoreRef.name,
    dbSyncMetaStoreRef.name,
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
  late var dbSyncMetaInfoRef = dbSyncMetaStoreRef.record('info');
  @override
  late var syncedDbSystemStoreNames = [
    dbSyncRecordStoreRef.name,
    dbSyncMetaStoreRef.name,
  ];

  /// Explicit sync stores
  List<SdbStoreRef<String, SdbModel>> get _syncStores =>
      syncedStoreNames.map((e) => SdbStoreRef<String, SdbModel>(e)).toList();

  var _closed = false;

  @override
  Future<void> close() async {
    if (!_closed && _database != null) {
      _closed = true;
      await _database?.close();
    }
  }
}

/// Synced db
abstract class SyncedSdb implements SyncedSdbCommon {
  /// Default name
  static String nameDefault = 'synced_sdb.db';

  // var dbSyncRecordStoreRef = cvIntStoreFactory.store<DbSyncRecord>('syncedR');
  // var dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>('syncedM');
  ScvStoreRef<int, SdbSyncRecord> get dbSyncRecordStoreRef;

  ScvStoreRef<String, SdbSyncMetaInfo> get dbSyncMetaStoreRef;

  ScvRecordRef<String, SdbSyncMetaInfo> get dbSyncMetaInfoRef;

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
  late bool trackChangesDisabled;

  Future<void> close();
}

extension SyncedDbExtension on SyncedSdb {
  static final _dirtyFilter = SdbFilter.equals(recordDirtyFieldKey, true);

  /// Get dirty record
  Future<List<SdbSyncRecord>> txnGetDirtySyncRecords(SdbClient client) async {
    // TODO optimize with index
    return (await dbSyncRecordStoreRef.findRecords(
      client,
      options: SdbFindOptions(filter: _dirtyFilter),
    )).toList();
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

  /// Disable change tracking during syncTransaction
  Future<T> syncTransaction<T>({
    List<String>? storeNames,
    SdbTransactionMode? mode,
    required FutureOr<T> Function(SdbTransaction transaction) run,
  }) async {
    return syncTransactionLock.synchronized(() async {
      try {
        return await transaction(
          storeNames: storeNames,
          mode: mode,
          run: (txn) async {
            try {
              trackChangesDisabled = true;
              var result = await run(txn);
              return result;
            } finally {}
          },
        );
      } finally {
        trackChangesDisabled = false;
      }
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
    await dbSyncRecordStoreRef.delete(client);
  }

  @visibleForTesting
  Future<void> clearMetaInfo(SdbClient? client) async {
    client ??= await database;
    await dbSyncMetaInfoRef.delete(client);
  }

  @visibleForTesting
  Future<void> clearAllSyncInfo(SdbClient? client) async {
    await clearMetaInfo(client);
    await clearSyncRecords(client);
  }

  /// Get sync records
  Future<List<SdbSyncRecord>> getSyncRecords({SdbClient? client}) async {
    client ??= await database;
    return (await dbSyncRecordStoreRef.findRecords(client)).toList();
  }

  Future<SdbSyncRecord?> getSyncRecord(
    SdbClient client,
    SdbRecordRef<dynamic, Map<String, Object?>> record,
  ) async {
    return await dbSyncRecordStoreRef.findRecord(
      client,
      filter: SdbFilter.and([
        SdbFilter.equals(dbSyncRecordModel.store.k, record.store.name),
        SdbFilter.equals(dbSyncRecordModel.key.k, record.key),
      ]),
    );
  }

  Future<SdbSyncRecord?> getSyncRecordAny(
    SdbClient client,
    SdbRecordRef record,
  ) async {
    // !! very slow
    return await dbSyncRecordStoreRef.findRecord(
      client,

      filter: SdbFilter.and([
        SdbFilter.equals(dbSyncRecordModel.store.k, record.store.name),
        SdbFilter.equals(dbSyncRecordModel.key.k, record.key),
      ]),
    );
  }

  Future<SdbSyncMetaInfo?> getSyncMetaInfo({SdbClient? client}) async {
    client ??= await database;
    var localMetaSyncInfo = await dbSyncMetaInfoRef.get(client);
    return localMetaSyncInfo;
  }

  /// Last sync change id
  Future<int?> getSyncMetaInfoLastChangeId({SdbClient? client}) async {
    var metaInfo = await getSyncMetaInfo(client: client);
    return metaInfo?.lastChangeId.v;
  }

  Stream<SdbSyncMetaInfo?> onSyncMetaInfo() async* {
    // ignore: unused_local_variable
    var db = await database;
    // TODO internally
    // yield* dbSyncMetaInfoRef.onRecord(db);
  }

  Stream<bool> onDirty() async* {
    // ignore: unused_local_variable
    var db = await database;
    // TODO implement onDirty
    /*
    yield* dbSyncRecordStoreRef
        .query(finder: _dirtyFinder)
        .onCount(db)
        .map((count) => count > 0);*/
  }

  /// Internal and test only.
  @protected
  Future<void> setSyncMetaInfo(
    SdbClient? client,
    SdbSyncMetaInfo? dbSyncMetaInfo,
  ) async {
    client ??= await database;

    if (dbSyncMetaInfo == null) {
      await dbSyncMetaInfoRef.delete(client);
    } else {
      if (!dbSyncMetaInfo.hasId) {
        dbSyncMetaInfo = dbSyncMetaInfoRef.cv()..copyFrom(dbSyncMetaInfo);
      }
      await dbSyncMetaInfo.put(client);
      //await dbSyncMetaInfoRef.cv(),
      /*
      client, dbSyncMetaInfo);
      ..lastChangeId.v = newLastChangeId
      ..lastTimestamp.v = newLastTimestamp
      ..sourceVersion.setValue(initialSourceMeta?.version.v))
        .put(txn);

       */
    }
  }

  /// Ready to use
  Future<void> get ready => database;
}

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
    dbSyncMetaStoreRef.schema(),
    dbSyncRecordStoreRef.schema(
      autoIncrement: true,
      indexes: [
        dbSyncRecordBySyncIndexRef.schema(
          keyPath: dbSyncRecordModel.syncId.name,
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
  ScvStoreRef<String, SdbSyncMetaInfo> get dbSyncMetaStoreRef =>
      sync.dbSyncMetaStoreRef;

  @override
  ScvStoreRef<int, SdbSyncRecord> get dbSyncRecordStoreRef =>
      sync.dbSyncRecordStoreRef;
}

SdbSyncRecord syncRecordFrom(SdbRecordRef<String, SdbModel> record) {
  return SdbSyncRecord()
    ..key.v = record.key
    ..store.v = record.store.name;
}

SdbSyncRecord syncRecordFromAny(SdbRecordRef record) {
  return SdbSyncRecord()
    ..key.v = record.key as String
    ..store.v = record.store.name;
}
