import 'package:tekaly_sembast_synced/synced_db_firestore.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore_v2.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Synced source firestore
class AutoSynchronizedFirestoreSyncedDbOptions
    implements AutoSynchronizedSyncedDbOptions {
  /// Synced db options
  final SyncedDbOptions syncedDbOptions;

  /// Firestore instance
  final Firestore firestore;

  /// Sembast db factory
  final DatabaseFactory databaseFactory;

  /// Root document path
  final String rootDocumentPath;

  /// Sembast db name
  final String sembastDbName;

  /// Synchronized stores, compat, prefer options
  List<String>? get synchronizedStores => syncedDbOptions.syncedStoreNames;

  /// Synchronized excluded stores, compat, prefer options,
  List<String>? get synchronizedExcludedStores =>
      syncedDbOptions.syncedExcludedStoreNames;

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedDbOptions({
    Firestore? firestore,
    SyncedDbOptions? syncedDbOptions,
    required this.databaseFactory,
    this.sembastDbName = 'synced.db',

    /// Default ok for tests only
    this.rootDocumentPath = 'test/local',
    List<String>? synchronizedStores,
    List<String>? synchronizedExcludedStores,
  }) : syncedDbOptions =
           syncedDbOptions ??
           SyncedDbOptions(
             syncedStoreNames: synchronizedStores,
             syncedExcludedStoreNames: synchronizedExcludedStores,
           ),
       firestore = firestore ?? Firestore.instance;
}

/// Auto synchronized firestore synced db
abstract class AutoSynchronizedFirestoreSyncedDb implements AutoSynchronizedDb {
  /// Synchronizer
  SyncedDbSynchronizer get synchronizer;

  /// Synced db
  SyncedDb get syncedDb;

  /// Options
  final AutoSynchronizedFirestoreSyncedDbOptions options;

  /// Database
  Database get database;

  /// Constructor
  AutoSynchronizedFirestoreSyncedDb({required this.options});

  /// Open
  static Future<AutoSynchronizedFirestoreSyncedDb> open({
    required AutoSynchronizedFirestoreSyncedDbOptions options,
  }) async {
    var db = _AutoSynchronizedFirestoreSyncedDb(options: options);
    await db.ready;
    return db;
  }

  /// Wait for first synchronization (could take forever if offline the first time)
  Future<void> initialSynchronizationDone();

  /// Close the db
  Future<void> close();

  /// Synchronize
  Future<SyncedSyncStat> synchronize();

  /// Lazy synchronize if needed (timing undefined) - same as synchronize as of 2026/02/05
  Future<SyncedSyncStat> lazySynchronize();

  /// Wait for current lazy synchronization to be done
  /// Future<void> waitSynchronized();
}

class _AutoSynchronizedFirestoreSyncedDb
    implements AutoSynchronizedFirestoreSyncedDb {
  @override
  late final SyncedDb syncedDb;
  @override
  late final SyncedDbSynchronizer synchronizer;

  /// Wait for first synchronization (could take forever if offline the first time)
  @override
  Future<void> initialSynchronizationDone() async {
    await syncedDb.initialSynchronizationDone();
  }

  @override
  Future<void> close() async {
    await synchronizer.close();
    await syncedDb.close();
  }

  @override
  late Database database;
  @override
  final AutoSynchronizedFirestoreSyncedDbOptions options;

  _AutoSynchronizedFirestoreSyncedDb({required this.options});

  late final ready = () async {
    syncedDb = SyncedDb.openDatabase(
      databaseFactory: options.databaseFactory,
      syncedExcludedStoreNames: options.synchronizedExcludedStores,
      syncedStoreNames: options.synchronizedStores,
      name: options.sembastDbName,
    );
    database = await syncedDb.database;
    synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: SyncedSourceFirestore(
        firestore: options.firestore,
        rootPath: options.rootDocumentPath,
      ),
      autoSync: true,
    );
  }();

  @override
  Future<SyncedSyncStat> lazySynchronize() async {
    await ready;
    return await synchronizer.lazySync();
  }

  @override
  Future<SyncedSyncStat> synchronize() async {
    await ready;
    return await synchronizer.sync();
  }
}
