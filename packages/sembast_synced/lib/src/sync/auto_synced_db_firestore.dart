import 'package:sembast/sembast.dart';
import 'package:tekaly_sembast_synced/synced_db_firestore.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore_v2.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Synced source firestore
class AutoSynchronizedFirestoreSyncedDbOptions
    implements AutoSynchronizedSyncedDbOptions {
  /// Firestore instance
  final Firestore firestore;

  /// Sembast db factory
  final DatabaseFactory databaseFactory;

  /// Root document path
  final String rootDocumentPath;

  /// Sembast db name
  final String sembastDbName;

  /// Synchronized stores
  final List<String>? synchronizedStores;

  /// Synchronized excluded stores
  final List<String>? synchronizedExcludedStores;

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedDbOptions({
    Firestore? firestore,
    required this.databaseFactory,
    this.sembastDbName = 'synced.db',

    /// Default ok for tests only
    this.rootDocumentPath = 'test/local',
    this.synchronizedStores,
    this.synchronizedExcludedStores,
  }) : firestore = firestore ?? Firestore.instance;
}

/// Auto synchronized firestore synced db
abstract class AutoSynchronizedFirestoreSyncedDb implements AutoSynchronizedDb {
  SyncedDb get syncedDb;

  final AutoSynchronizedFirestoreSyncedDbOptions options;

  Database get database;

  AutoSynchronizedFirestoreSyncedDb({required this.options});

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

  Future<SyncedSyncStat> synchronize();

  /// Lazy synchronize if needed (timing undefined)
  Future<SyncedSyncStat> lazySynchronize();

  /// Wait for current lazy synchronization to be done
  /// Future<void> waitSynchronized();
}

class _AutoSynchronizedFirestoreSyncedDb
    implements AutoSynchronizedFirestoreSyncedDb {
  @override
  late final SyncedDb syncedDb;
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
