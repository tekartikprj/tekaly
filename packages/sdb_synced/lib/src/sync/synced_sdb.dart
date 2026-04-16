import 'package:idb_shim/idb_client_logger.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart' as sync;
import 'package:tekaly_sdb_synced/src/model/db_sync_record.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Synced SDB mixin.
mixin SyncedSdbMixin implements SyncedSdb {
  /// Database factory.
  late final SdbFactory databaseFactory;

  /// True when first synchronization is done (even without data, i.e. last ChangeId should be zero)
  @override
  Future<void> initialSynchronizationDone() async {
    onSyncMetaInfo().listen((data) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('initialSynchronizationDone meta info $data');
      }
    });
    await onSyncMetaInfo().firstWhere((meta) => meta?.lastChangeId != null);
  }
}

/// Debug flag for synced sdb.
var syncedSdbDebug = false; // devWarning(true);

var _buildersInitialized = false;

/// Initialize cv builders for synced db.
void cvInitSyncedDbBuilders() {
  if (!_buildersInitialized) {
    _buildersInitialized = true;

    cvAddConstructor(SdbSyncRecord.new);
    cvAddConstructor(SdbSyncMetaInfo.new);
  }
}

/// Synced SDB base class.
abstract class SyncedSdbBase with SyncedSdbMixin {
  final _syncMetaInfoSubject = BehaviorSubject<SdbSyncMetaInfo?>();
  final _syncDirtySubject = PublishSubject<bool>();

  /// Options for synced sdb.
  final SyncedSdbOptions options;

  /// Synced SDB base constructor.
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

  /// On changes listener.
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

  /// On changes listener for any record.
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

  late final Set<String> _syncedStoreNames;

  List<String> get _syncedDbSystemStoreNames => [
    sdbSyncRecordStoreRef.name,
    sdbSyncMetaStoreRef.name,
  ];
  @override
  late final database = () async {
    return _database ??= (await rawDatabase.then((db) {
      var syncedStoreNames = Set.of(db.storeNames);
      syncedStoreNames
        ..removeAll(_syncedDbSystemStoreNames)
        ..removeWhere(
          (name) => name.startsWith(SyncedSdb.unsyncedStoreNamePrefix),
        );
      var extraStoreNames = _syncedDbSystemStoreNames;
      _syncedStoreNames = syncedStoreNames;
      // Setup triggers
      for (var store in _syncedStores) {
        store.addOnChangesListener(
          db,
          onChanges,
          extraStoreNames: extraStoreNames,
        );
      }

      return db;
    }))!;
  }();

  @override
  late var scvSyncMetaInfoRef = sdbSyncMetaStoreRef.record('info');
  @override
  late var syncedDbSystemStoreNames = [
    sdbSyncRecordStoreRef.name,
    sdbSyncMetaStoreRef.name,
  ];

  /// Explicit sync stores
  List<SdbStoreRef<String, SdbModel>> get _syncedStores =>
      _syncedStoreNames.map((e) => SdbStoreRef<String, SdbModel>(e)).toList();

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

/// Synced SDB.
abstract class SyncedSdb implements SyncedDbCommon {
  /// Prefix for local stores (un synced)
  static const unsyncedStoreNamePrefix = 'local_';

  /// Default name
  static String nameDefault = 'synced_sdb.db';

  /// Sync record store ref.
  ScvStoreRef<int, SdbSyncRecord> get scvSyncRecordStoreRef;

  /// Sync meta store ref.
  ScvStoreRef<String, SdbSyncMetaInfo> get scvSyncMetaStoreRef;

  /// Sync meta info record ref.
  ScvRecordRef<String, SdbSyncMetaInfo> get scvSyncMetaInfoRef;

  /// Sync transaction lock.
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

  /// Create from an opened database.
  factory SyncedSdb.fromOpenedDb({
    SdbDatabase? openedDatabase,
    required SyncedSdbOptions options,
  }) => _SyncedSdbImpl(options: options, openedDatabase: openedDatabase);

  /// Open database.
  static SyncedSdb openDatabase({
    String? name,
    required SdbFactory databaseFactory,
    required SyncedSdbOptions options,
  }) =>
      SyncedSdb(options: options, name: name, databaseFactory: databaseFactory);

  /// Raw database access.
  Future<SdbDatabase> get rawDatabase;

  /// Database access.
  Future<SdbDatabase> get database;

  /// System store names.
  List<String> get syncedDbSystemStoreNames;

  /// Visible only for testing
  @visibleForTesting
  bool get trackChangesDisabled;

  /// Close database.
  Future<void> close();
}

/// Private extension
extension SyncedSdbPrvExtension on SyncedSdb {
  /// Computed on open, actual store names synced
  @visibleForTesting
  List<String> get syncedStoreNames => _impl._syncedStoreNames.toList();
}

/// Synced SDB extension.
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

  /// Clear sync records.
  @visibleForTesting
  Future<void> clearSyncRecords(SdbClient? client) async {
    client ??= await database;
    await sdbSyncRecordStoreRef.delete(client);
  }

  /// Clear meta info.
  @visibleForTesting
  Future<void> clearMetaInfo(SdbClient? client) async {
    client ??= await database;
    await scvSyncMetaInfoRef.delete(client);
  }

  /// Clear all sync info.
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

  /// Get sync record.
  Future<SdbSyncRecord?> getSyncRecord(
    SdbClient client,
    SdbRecordRef<String, Map<String, Object?>> record,
  ) {
    return sdbSyncRecordByStoreAndKeyIndexRef
        .record(record.store.name, record.key)
        .getObject(client);
  }

  /// Get sync record by any record ref.
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

  /// Get sync meta info.
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

  /// On dirty changes.
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

/// Synced SDB options.
class SyncedSdbOptions {
  /// Open database options.
  final SdbOpenDatabaseOptions openDatabaseOptions;

  /// Synced SDB options constructor.
  SyncedSdbOptions({required this.openDatabaseOptions});

  /// Copy with
  SyncedSdbOptions copyWith({SdbOpenDatabaseOptions? openDatabaseOptions}) {
    return SyncedSdbOptions(
      openDatabaseOptions: openDatabaseOptions ?? this.openDatabaseOptions,
    );
  }
}

/// Synced SDB meta schema.
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
    required super.options,
    String? name,
  }) : name = name ?? SyncedSdb.nameDefault {
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
          options: options.openDatabaseOptions,
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
/// Synced SDB record ref.
typedef SyncedSdbRecordRef = SdbRecordRef<String, SdbModel>;

/// Create a sync record from a synced sdb record ref.
SdbSyncRecord syncRecordFrom(SyncedSdbRecordRef record) {
  return SdbSyncRecord()
    ..key.v = record.key
    ..store.v = record.store.name;
}

/// Create a sync record from any sdb record ref.
SdbSyncRecord syncRecordFromAny(SdbRecordRef record) {
  return SdbSyncRecord()
    ..key.v = record.key as String
    ..store.v = record.store.name;
}
