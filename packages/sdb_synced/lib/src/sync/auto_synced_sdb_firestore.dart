import 'package:idb_shim/idb_sdb.dart';
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore_v2.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'auto_synced_sdb.dart';

/// Synced source firestore
class AutoSynchronizedFirestoreSyncedSdbOptions
    implements AutoSynchronizedSyncedSdbOptions {
  /// Synced db options
  final SyncedSdbOptions syncedSdbOptions;

  /// Firestore instance
  final Firestore firestore;

  /// Sembast db factory
  final SdbFactory databaseFactory;

  /// Root document path
  final String rootDocumentPath;

  /// Sembast db name
  final String dbName;

  /// Read-only: only sync down, local changes are never pushed to firestore
  /// (a public source the user cannot write to).
  final bool readOnly;

  /// Retry strategy when a synchronization fails (the network is down...),
  /// the default one retries every 5s until the first synchronization is
  /// done, then every 15s up to 1 minute.
  final SyncedDbSynchronizerRetryOptions retryOptions;

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedSdbOptions({
    Firestore? firestore,
    required this.syncedSdbOptions,
    required this.databaseFactory,
    required this.dbName,
    this.readOnly = false,
    SyncedDbSynchronizerRetryOptions? retryOptions,

    /// Default ok for tests only
    this.rootDocumentPath = 'test/local',
  }) : firestore = firestore ?? Firestore.instance,
       retryOptions =
           retryOptions ?? const SyncedDbSynchronizerRetryOptions();
}

/// Auto synchronized firestore synced db
abstract class AutoSynchronizedFirestoreSyncedSdb
    implements AutoSynchronizedSdb {
  /// Synchronizer
  SyncedSdbSynchronizer get synchronizer;

  /// Synced db
  SyncedSdb get syncedSdb;

  /// Options
  final AutoSynchronizedFirestoreSyncedSdbOptions options;

  /// Database, valid when ready
  SdbDatabase get database;

  /// Constructor
  AutoSynchronizedFirestoreSyncedSdb({required this.options});

  /// Open
  static Future<AutoSynchronizedFirestoreSyncedSdb> open({
    required AutoSynchronizedFirestoreSyncedSdbOptions options,
  }) async {
    var db = _AutoSynchronizedFirestoreSyncedSdb(options: options);
    await db.ready;
    return db;
  }

  /// Wait for the first synchronization.
  ///
  /// A failed synchronization is retried (see
  /// [AutoSynchronizedFirestoreSyncedSdbOptions.retryOptions]), so this
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

class _AutoSynchronizedFirestoreSyncedSdb
    implements AutoSynchronizedFirestoreSyncedSdb {
  @override
  late final SyncedSdb syncedSdb;
  @override
  late final SyncedSdbSynchronizer synchronizer;

  /// Wait for the first synchronization, retried when it fails.
  @override
  Future<void> initialSynchronizationDone() async {
    await ready;
    await syncedSdb.initialSynchronizationDone();
  }

  @override
  Future<void> close() async {
    await synchronizer.close();
    await syncedSdb.close();
  }

  @override
  late SdbDatabase database;
  @override
  final AutoSynchronizedFirestoreSyncedSdbOptions options;

  _AutoSynchronizedFirestoreSyncedSdb({required this.options});

  late final ready = () async {
    syncedSdb = SyncedSdb.openDatabase(
      options: options.syncedSdbOptions,
      databaseFactory: options.databaseFactory,
      name: options.dbName,
    );
    database = await syncedSdb.database;
    var source = SyncedSourceFirestore(
      firestore: options.firestore,
      rootPath: options.rootDocumentPath,
    );
    synchronizer = options.readOnly
        ? SyncedSdbSynchronizer(
            db: syncedSdb,
            readSource: source,
            autoSync: true,
            retryOptions: options.retryOptions,
          )
        : SyncedSdbSynchronizer(
            db: syncedSdb,
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
