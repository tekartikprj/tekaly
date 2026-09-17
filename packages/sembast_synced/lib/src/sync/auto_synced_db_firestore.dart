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

  /// Read-only: only sync down, local changes are never pushed to firestore
  /// (a public source the user cannot write to).
  final bool readOnly;

  /// Retry strategy when a synchronization fails (the network is down...).
  /// By default, while the first synchronization is pending, every 5s during
  /// 1 minute then growing to reach 1 minute after 5 minutes of retrying;
  /// once it is done, 15s doubled on each failure up to 1 minute.
  final SyncedDbSynchronizerRetryOptions retryOptions;

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedDbOptions({
    Firestore? firestore,
    SyncedDbOptions? syncedDbOptions,
    required this.databaseFactory,
    this.sembastDbName = 'synced.db',
    this.readOnly = false,
    SyncedDbSynchronizerRetryOptions? retryOptions,

    /// Default ok for tests only
    this.rootDocumentPath = 'test/local',
  }) : syncedDbOptions = syncedDbOptions ?? SyncedDbOptions(),
       firestore = firestore ?? Firestore.instance,
       retryOptions = retryOptions ?? const SyncedDbSynchronizerRetryOptions();
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

  /// Wait for the first synchronization.
  ///
  /// A failed synchronization is retried (see
  /// [AutoSynchronizedFirestoreSyncedDbOptions.retryOptions]), so this
  /// terminates once the source becomes reachable, it does not wait forever
  /// when the network is down when the database is opened.
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

  /// Wait for the first synchronization, retried when it fails.
  @override
  Future<void> initialSynchronizationDone() async {
    await ready;
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
      options: options.syncedDbOptions,
      name: options.sembastDbName,
    );
    database = await syncedDb.database;
    var source = SyncedSourceFirestore(
      firestore: options.firestore,
      rootPath: options.rootDocumentPath,
    );
    synchronizer = options.readOnly
        ? SyncedDbSynchronizer(
            db: syncedDb,
            readSource: source,
            autoSync: true,
            retryOptions: options.retryOptions,
          )
        : SyncedDbSynchronizer(
            db: syncedDb,
            source: source,
            autoSync: true,
            retryOptions: options.retryOptions,
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
