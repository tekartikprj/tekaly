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

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedSdbOptions({
    Firestore? firestore,
    required this.syncedSdbOptions,
    required this.databaseFactory,
    required this.dbName,

    /// Default ok for tests only
    this.rootDocumentPath = 'test/local',
  }) : firestore = firestore ?? Firestore.instance;
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

class _AutoSynchronizedFirestoreSyncedSdb
    implements AutoSynchronizedFirestoreSyncedSdb {
  @override
  late final SyncedSdb syncedSdb;
  @override
  late final SyncedSdbSynchronizer synchronizer;

  /// Wait for first synchronization (could take forever if offline the first time)
  @override
  Future<void> initialSynchronizationDone() async {
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
    synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
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
