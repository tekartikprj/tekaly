import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart' as sync;
import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Synced db timestamp (sembast based)
typedef SyncedDbTimestamp = ScvTimestamp;

mixin SyncedDbMixin implements SyncedSdb {
  late final SdbFactory databaseFactory;
  @override
  late final List<String> syncedStoreNames;
  @override
  late final List<String>? syncedExcludedStoreNames;

  /// True when first synchronization is done (even without data, i.e. last ChangeId should be zero)
  @override
  Future<void> initialSynchronizationDone() async {
    await onSyncMetaInfo().firstWhere((meta) => meta?.lastChangeId != null);
  }
}

var syncedDbDebug = false; // devWarning(true);

var _buildersInitialized = false;

void cvInitSyncedDbBuilders() {
  if (!_buildersInitialized) {
    _buildersInitialized = true;

    cvAddConstructor(DbSyncRecord.new);
    cvAddConstructor(DbSyncMetaInfo.new);
  }
}

abstract class SyncedDbBase with SyncedDbMixin {
  SyncedDbBase() {
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
    await onChangesAny(txn, changes);
  }

  // Type unsafe assuming string, map
  Future<void> onChangesAny(
    SdbTransaction txn,
    List<SdbRecordChange> changes,
  ) async {
    for (var change in changes) {
      var changeRef = change.ref;
      if (syncedDbDebug) {
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

  @override
  Future<SdbDatabase> get database async =>
      _database ??= (await rawDatabase.then((db) {
        // Setup triggers
        for (var store in _syncStores) {
          store.addOnChangesListener(db, onChanges);
        }
        if (_syncStores.isEmpty) {
          for (var store in _allStoresButMeta(db)) {
            store.addOnChangesListener(db, onChanges);
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
abstract class SyncedSdb implements SyncedDbCommon {
  /// Default name
  static String nameDefault = 'synced_sdb.db';

  // var dbSyncRecordStoreRef = cvIntStoreFactory.store<DbSyncRecord>('syncedR');
  // var dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>('syncedM');
  ScvStoreRef<int, DbSyncRecord> get dbSyncRecordStoreRef;

  /// Synced store
  // List<CvStoreRef<String, DbStringRecordBase>> get syncStores;

  List<String>? get syncedStoreNames;

  /// USed if synced store names is empty, to excluded some stores
  List<String>? get syncedExcludedStoreNames;

  ScvStoreRef<String, DbSyncMetaInfo> get dbSyncMetaStoreRef;

  ScvRecordRef<String, DbSyncMetaInfo> get dbSyncMetaInfoRef;

  @protected
  Lock get syncTransactionLock;

  /// True when first synchronization is done (even without data, i.e. last ChangeId can be null but should be 0)
  Future<void> initialSynchronizationDone();

  /// Good for in memory manipulation of incomping data and unit test !
  factory SyncedSdb.newInMemory({
    required SyncedSdbOptions options,
    List<String>? syncedStoreNames,
  }) => _SyncedDbInMemory(syncedStoreNames: syncedStoreNames, options: options);

  /// Constructor
  factory SyncedSdb({
    String? name,
    required SdbFactory databaseFactory,
    required SyncedSdbOptions schema,
    List<String>? syncedExcludedStoreNames,
    List<String>? syncedStoreNames,
  }) => _SyncedDbImpl(
    name: name,
    databaseFactory: databaseFactory,
    options: schema,
    syncedExcludedStoreNames: syncedExcludedStoreNames,
    syncedStoreNames: syncedStoreNames,
  );

  factory SyncedSdb.fromOpenedDb({
    SdbDatabase? openedDatabase,
    List<String>? syncedStoreNames,
    List<String>? syncedExcludedStoreNames,
    required SyncedSdbOptions options,
  }) => _SyncedDbImpl(
    options: options,
    openedDatabase: openedDatabase,
    syncedStoreNames: syncedStoreNames,
    syncedExcludedStoreNames: syncedExcludedStoreNames,
  );

  static SyncedSdb openDatabase({
    String? name,
    required SdbFactory databaseFactory,
    List<String>? syncedExcludedStoreNames,
    List<String>? syncedStoreNames,
    required SyncedSdbOptions options,
  }) => SyncedSdb(
    schema: options,
    name: name,
    databaseFactory: databaseFactory,
    syncedExcludedStoreNames: syncedExcludedStoreNames,
    syncedStoreNames: syncedStoreNames,
  );

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
  Future<List<DbSyncRecord>> txnGetDirtySyncRecords(SdbClient client) async {
    // TODO optimize with index
    return (await dbSyncRecordStoreRef.findRecords(
      client,
      options: SdbFindOptions(filter: _dirtyFilter),
    )).toList();
  }

  Iterable<String> allStoreNamesButSynced(SdbDatabase db) {
    var storeNames = db.storeNames;
    return storeNames.where(
      (name) =>
          !(syncedStoreNames != null && syncedStoreNames!.contains(name)) &&
          !(syncedExcludedStoreNames != null &&
              syncedExcludedStoreNames!.contains(name)),
    );
  }

  Iterable<SdbStoreRef> _allStores(SdbDatabase db) {
    var storeNames = db.storeNames;
    return storeNames.map((e) => SdbStoreRef<String, SdbModel>(e));
  }

  Iterable<SdbStoreRef<String, SdbModel>> _allStoresButMeta(SdbDatabase db) =>
      allStoreNamesButSynced(
        db,
      ).map((e) => SdbStoreRef<String, SdbModel>(e)).toList();

  /// Run in transaction.
  Future<T> transaction<T>(
    FutureOr<T> Function(SdbTransaction transaction) action, {
    required SdbTransactionMode mode,
  }) async {
    var db = await database;
    return db.inStoresTransaction(_allStores(db).toList(), mode, (txn) {
      return action(txn);
    });
  }

  /// Disable change tracking during syncTransaction
  Future<T> syncTransaction<T>(
    FutureOr<T> Function(SdbTransaction transaction) action,
  ) async {
    return syncTransactionLock.synchronized(() async {
      try {
        return await transaction((txn) async {
          try {
            trackChangesDisabled = true;
            var result = await action(txn);
            return result;
          } finally {
            trackChangesDisabled = false;
          }
        }, mode: SdbTransactionMode.readWrite);
      } finally {}
    });
  }

  /// Raw access
  Future<void> txnPutSyncRecord(SdbClient? client, DbSyncRecord record) async {
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
  Future<List<DbSyncRecord>> getSyncRecords({SdbClient? client}) async {
    client ??= await database;
    return (await dbSyncRecordStoreRef.findRecords(client)).toList();
  }

  Future<DbSyncRecord?> getSyncRecord(
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

  Future<DbSyncRecord?> getSyncRecordAny(
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

  Future<DbSyncMetaInfo?> getSyncMetaInfo({SdbClient? client}) async {
    client ??= await database;
    var localMetaSyncInfo = await dbSyncMetaInfoRef.get(client);
    return localMetaSyncInfo;
  }

  /// Last sync change id
  Future<int?> getSyncMetaInfoLastChangeId({SdbClient? client}) async {
    var metaInfo = await getSyncMetaInfo(client: client);
    return metaInfo?.lastChangeId.v;
  }

  Stream<DbSyncMetaInfo?> onSyncMetaInfo() async* {
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
    DbSyncMetaInfo? dbSyncMetaInfo,
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

class _SyncedDbInMemory extends _SyncedDbImpl {
  static SdbFactory get inMemoryDatabaseFactory => newSdbFactoryMemory();

  //static DatabaseFactory get inMemoryDatabaseFactory => SqfliteLogget newDatabaseFactoryMemory();
  @visibleForTesting
  _SyncedDbInMemory({
    required super.syncedStoreNames,
    super.syncedExcludedStoreNames,
    required super.options,
  }) : super(databaseFactory: inMemoryDatabaseFactory);
}

class SyncedSdbOptions {
  final SdbDatabaseSchema schema;
  final int version;

  SyncedSdbOptions({required this.schema, required this.version});
}

final syncedSdbMetaSchema = SdbDatabaseSchema(
  stores: [dbSyncMetaStoreRef.schema(), dbSyncRecordStoreRef.schema()],
);

/// Default implementation
class _SyncedDbImpl extends SyncedDbBase implements SyncedSdb {
  final SyncedSdbOptions options;

  String name;

  final SdbDatabase? openedDatabase;

  //static DatabaseFactory get inMemoryDatabaseFactory => SqfliteLogget newDatabaseFactoryMemory();
  @visibleForTesting
  _SyncedDbImpl({
    SdbFactory? databaseFactory,
    this.openedDatabase,
    required this.options,
    List<String>? syncedStoreNames,
    required List<String>? syncedExcludedStoreNames,
    String? name,
  }) : name = name ?? SyncedSdb.nameDefault {
    if (databaseFactory != null) {
      this.databaseFactory = databaseFactory;
    }
    this.syncedStoreNames = syncedStoreNames ?? <String>[];

    if (this.syncedStoreNames.isEmpty) {
      var excluded = syncedExcludedStoreNames?.toSet() ?? <String>{};
      excluded.addAll(syncedDbSystemStoreNames);
      this.syncedExcludedStoreNames = excluded.toList();
    } else {
      this.syncedExcludedStoreNames = syncedExcludedStoreNames;
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
  ScvStoreRef<String, DbSyncMetaInfo> get dbSyncMetaStoreRef =>
      sync.dbSyncMetaStoreRef;

  @override
  ScvStoreRef<int, DbSyncRecord> get dbSyncRecordStoreRef =>
      sync.dbSyncRecordStoreRef;
}

DbSyncRecord syncRecordFrom(SdbRecordRef<String, SdbModel> record) {
  return DbSyncRecord()
    ..key.v = record.key
    ..store.v = record.store.name;
}

DbSyncRecord syncRecordFromAny(SdbRecordRef record) {
  return DbSyncRecord()
    ..key.v = record.key as String
    ..store.v = record.store.name;
}
