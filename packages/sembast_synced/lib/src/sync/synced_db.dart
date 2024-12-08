import 'package:sembast/sembast_memory.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'model/db_sync_meta.dart';
import 'model/db_sync_record.dart';

mixin SyncedDbMixin implements SyncedDb {
  late final DatabaseFactory databaseFactory;
  @override
  late final List<String> syncedStoreNames;
  @override
  late final List<String>? syncedExcludedStoreNames;
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

  Database? _database;

  Future<void> onChanges(Transaction txn,
      List<RecordChange<String, Map<String, Object?>>> changes) async {
    await onChangesAny(txn, changes);
  }

  // Type unsafe assuming string, map
  Future<void> onChangesAny(Transaction txn, List<RecordChange> changes) async {
    for (var change in changes) {
      var changeRef = change.ref;
      if (syncedDbDebug) {
        print('change: ${change.oldSnapshot} => ${change.newSnapshot}');
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
                  ..deleted.v = true));
          } else {
            await dbSyncRecordStoreRef.add(
                txn, (syncRecordFromAny(changeRef)..dirty.v = true));
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
  Future<Database> get database async =>
      _database ??= (await rawDatabase.then((db) {
        // Setup triggers
        for (var store in _syncStores) {
          store.rawRef.addOnChangesListener(db, onChanges);
        }
        if (_syncStores.isEmpty) {
          db.addAllStoresOnChangesListener(onChangesAny,
              excludedStoreNames: syncedExcludedStoreNames);
        }
        return db;
      }))!;

  @override
  late var dbSyncMetaInfoRef = dbSyncMetaStoreRef.record('info');
  @override
  late var syncedDbSystemStoreNames = [
    dbSyncRecordStoreRef.name,
    dbSyncMetaStoreRef.name
  ];

  /// Deprecated
  @Deprecated('do not use')
  List<CvStoreRef<String, DbStringRecordBase>> get syncStores => _syncStores;

  /// Expplicit sync stores
  List<CvStoreRef<String, DbStringRecordBase>> get _syncStores =>
      syncedStoreNames
          .map((e) => cvStringStoreFactory.store<DbStringRecordBase>(e))
          .toList();

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
abstract class SyncedDb {
  /// Default name
  static String nameDefault = 'synced.db';
  // var dbSyncRecordStoreRef = cvIntStoreFactory.store<DbSyncRecord>('syncedR');
  // var dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>('syncedM');
  CvStoreRef<int, DbSyncRecord> get dbSyncRecordStoreRef;

  /// Synced store
  // List<CvStoreRef<String, DbStringRecordBase>> get syncStores;

  List<String>? get syncedStoreNames;

  /// USed if synced store names is empty, to excluded some stores
  List<String>? get syncedExcludedStoreNames;

  CvStoreRef<String, DbSyncMetaInfo> get dbSyncMetaStoreRef;

  CvRecordRef<String, DbSyncMetaInfo> get dbSyncMetaInfoRef;

  Lock get syncTransactionLock;

  /// True when first synchronization is done (even without data, i.e. last ChangeId can be null)
  Future<void> initialSynchronizationDone();

  /// Good for in memory manipulation of incomping data and unit test !
  factory SyncedDb.newInMemory({required List<String> syncedStoreNames}) =>
      _SyncedDbInMemory(syncedStoreNames: syncedStoreNames);

  factory SyncedDb(
          {String? name,
          required DatabaseFactory databaseFactory,
          List<String>? syncedExcludedStoreNames,
          List<String>? syncedStoreNames}) =>
      _SyncedDbImpl(
          name: name,
          databaseFactory: databaseFactory,
          syncedExcludedStoreNames: syncedExcludedStoreNames,
          syncedStoreNames: syncedStoreNames);
  factory SyncedDb.fromOpenedDb(
          {Database? openedDatabase,
          required List<String> syncedStoreNames,
          List<String>? syncedExcludedStoreNames}) =>
      _SyncedDbImpl(
          openedDatabase: openedDatabase,
          syncedStoreNames: syncedStoreNames,
          syncedExcludedStoreNames: syncedExcludedStoreNames);

  static SyncedDb openDatabase(
          {String? name,
          required DatabaseFactory databaseFactory,
          List<String>? syncedExcludedStoreNames,
          List<String>? syncedStoreNames}) =>
      SyncedDb(
          name: name,
          databaseFactory: databaseFactory,
          syncedExcludedStoreNames: syncedExcludedStoreNames,
          syncedStoreNames: syncedStoreNames);
  Future<Database> get rawDatabase;

  Future<Database> get database;

  List<String> get syncedDbSystemStoreNames;

  /// Visible only for testing
  @visibleForTesting
  late bool trackChangesDisabled;

  Future<void> close();
}

extension SyncedDbExtension on SyncedDb {
  static final _dirtyFinder =
      Finder(filter: Filter.equals(recordDirtyFieldKey, true));

  /// Get dirty record
  Future<List<DbSyncRecord>> txnGetDirtySyncRecords(
      DatabaseClient client) async {
    return (await dbSyncRecordStoreRef.find(client, finder: _dirtyFinder))
        .toList();
  }

  /// Run in transaction.
  Future<T> transaction<T>(
      FutureOr<T> Function(Transaction transaction) action) async {
    var db = await database;
    return db.transaction(action);
  }

  /// Disable change tracking during syncTransaction
  Future<T> syncTransaction<T>(
      FutureOr<T> Function(Transaction transaction) action) async {
    return syncTransactionLock.synchronized(() async {
      try {
        var db = await database;
        return await db.transaction((txn) async {
          try {
            trackChangesDisabled = true;
            var result = await action(txn);
            return result;
          } finally {
            trackChangesDisabled = false;
          }
        });
      } finally {}
    });
  }

  /// Raw access
  Future<void> txnPutSyncRecord(
      DatabaseClient? client, DbSyncRecord record) async {
    client ??= await database;
    await record.put(client, merge: true);
  }

  @visibleForTesting
  Future<void> clearSyncRecords(DatabaseClient? client) async {
    client ??= await database;
    await dbSyncRecordStoreRef.delete(client);
  }

  @visibleForTesting
  Future<void> clearMetaInfo(DatabaseClient? client) async {
    client ??= await database;
    await dbSyncMetaInfoRef.delete(client);
  }

  @visibleForTesting
  Future<void> clearAllSyncInfo(DatabaseClient? client) async {
    await clearMetaInfo(client);
    await clearSyncRecords(client);
  }

  /// Get sync records
  Future<List<DbSyncRecord>> getSyncRecords({DatabaseClient? client}) async {
    client ??= await database;
    return (await dbSyncRecordStoreRef.find(
      client,
    ))
        .toList();
  }

  Future<DbSyncRecord?> getSyncRecord(DatabaseClient client,
      RecordRef<dynamic, Map<String, Object?>> record) async {
    return await dbSyncRecordStoreRef.findFirst(client,
        finder: Finder(
            filter:
                Filter.equals(dbSyncRecordModel.store.k, record.store.name) &
                    Filter.equals(dbSyncRecordModel.key.k, record.key)));
  }

  Future<DbSyncRecord?> getSyncRecordAny(
      DatabaseClient client, RecordRef record) async {
    return await dbSyncRecordStoreRef.findFirst(client,
        finder: Finder(
            filter:
                Filter.equals(dbSyncRecordModel.store.k, record.store.name) &
                    Filter.equals(dbSyncRecordModel.key.k, record.key)));
  }

  Future<DbSyncMetaInfo?> getSyncMetaInfo({DatabaseClient? client}) async {
    client ??= await database;
    var localMetaSyncInfo = await dbSyncMetaInfoRef.get(client);
    return localMetaSyncInfo;
  }

  /// Last sync change id
  Future<int?> getSyncMetaInfoLastChangeId({DatabaseClient? client}) async {
    var metaInfo = await getSyncMetaInfo(client: client);
    return metaInfo?.lastChangeId.v;
  }

  Stream<DbSyncMetaInfo?> onSyncMetaInfo() async* {
    var db = await database;
    yield* dbSyncMetaInfoRef.onRecord(db);
  }

  Stream<bool> onDirty() async* {
    var db = await database;
    yield* dbSyncRecordStoreRef
        .query(finder: _dirtyFinder)
        .onCount(db)
        .map((count) => count > 0);
  }

  /// Internal and test only.
  @protected
  Future<void> setSyncMetaInfo(
      DatabaseClient? client, DbSyncMetaInfo? dbSyncMetaInfo) async {
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
  static DatabaseFactory get inMemoryDatabaseFactory =>
      newDatabaseFactoryMemory();

  //static DatabaseFactory get inMemoryDatabaseFactory => SqfliteLogget newDatabaseFactoryMemory();
  @visibleForTesting
  _SyncedDbInMemory(
      {required super.syncedStoreNames, super.syncedExcludedStoreNames})
      : super(databaseFactory: inMemoryDatabaseFactory);
}

/// Default implementation
class _SyncedDbImpl extends SyncedDbBase
    with SyncedDbMixin
    implements SyncedDb {
  String name;

  final Database? openedDatabase;
  //static DatabaseFactory get inMemoryDatabaseFactory => SqfliteLogget newDatabaseFactoryMemory();
  @visibleForTesting
  _SyncedDbImpl(
      {DatabaseFactory? databaseFactory,
      this.openedDatabase,
      List<String>? syncedStoreNames,
      required List<String>? syncedExcludedStoreNames,
      String? name})
      : name = name ?? SyncedDb.nameDefault {
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

  @override
  final dbSyncMetaStoreRef =
      cvStringStoreFactory.store<DbSyncMetaInfo>('syncMeta');
  @override
  final dbSyncRecordStoreRef =
      cvIntStoreFactory.store<DbSyncRecord>('syncRecord');

  /// True when first synchronization is done (even without data, i.e. last ChangeId should be zero)
  @override
  Future<void> initialSynchronizationDone() async {
    await onSyncMetaInfo().firstWhere((meta) => meta?.lastChangeId != null);
  }

  @override
  late final rawDatabase = openedDatabase != null
      ? Future.value(openedDatabase)
      : databaseFactory.openDatabase(name);
}

DbSyncRecord syncRecordFrom(RecordRef<String, Map<String, Object?>> record) {
  return DbSyncRecord()
    ..key.v = record.key
    ..store.v = record.store.name;
}

DbSyncRecord syncRecordFromAny(RecordRef record) {
  return DbSyncRecord()
    ..key.v = record.key as String
    ..store.v = record.store.name;
}
