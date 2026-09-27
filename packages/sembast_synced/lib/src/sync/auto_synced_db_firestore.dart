import 'package:tekaly_sembast_synced/synced_db_firestore.dart';
import 'package:tekaly_synced_db_common/synced_db_common_firestore.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Synced source firestore
class AutoSynchronizedFirestoreSyncedDbOptions
    extends AutoSynchronizedFirestoreOptionsCommon
    implements AutoSynchronizedSyncedDbOptions {
  /// Synced db options
  final SyncedDbOptions syncedDbOptions;

  /// Sembast db factory
  final DatabaseFactory databaseFactory;

  /// Sembast db name
  final String sembastDbName;

  /// Synchronized stores, compat, prefer options
  List<String>? get synchronizedStores => syncedDbOptions.syncedStoreNames;

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedDbOptions({
    super.firestore,
    SyncedDbOptions? syncedDbOptions,
    required this.databaseFactory,
    this.sembastDbName = 'synced.db',
    super.readOnly = false,
    super.retryOptions,

    /// Default ok for tests only
    super.rootDocumentPath = 'test/local',
  }) : syncedDbOptions = syncedDbOptions ?? SyncedDbOptions();
}

/// Auto synchronized firestore synced db
abstract class AutoSynchronizedFirestoreSyncedDb
    implements AutoSynchronizedDb, AutoSynchronizedFirestoreSyncedDbCommon {
  /// Synchronizer
  @override
  SyncedDbSynchronizer get synchronizer;

  /// Synced db
  SyncedDb get syncedDb;

  /// Options
  @override
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

  /// Wait for current lazy synchronization to be done
  /// Future<void> waitSynchronized();
}

class _AutoSynchronizedFirestoreSyncedDb
    extends
        AutoSynchronizedFirestoreSyncedDbBase<SyncedDb, SyncedDbSynchronizer>
    implements AutoSynchronizedFirestoreSyncedDb {
  @override
  late Database database;
  @override
  final AutoSynchronizedFirestoreSyncedDbOptions options;

  _AutoSynchronizedFirestoreSyncedDb({required this.options});

  @override
  Future<SyncedDb> openSyncedDb() async {
    var syncedDb = SyncedDb.openDatabase(
      databaseFactory: options.databaseFactory,
      options: options.syncedDbOptions,
      name: options.sembastDbName,
    );
    database = await syncedDb.database;
    return syncedDb;
  }

  @override
  SyncedDbSynchronizer newSynchronizer(
    SyncedDb syncedDb, {
    SyncedSource? source,
    SyncedSourceRead? readSource,
    required bool autoSync,
    required SyncedDbSynchronizerRetryOptions retryOptions,
  }) => SyncedDbSynchronizer(
    db: syncedDb,
    source: source,
    readSource: readSource,
    autoSync: autoSync,
    retryOptions: retryOptions,
  );
}
