import 'package:idb_shim/idb_sdb.dart';
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekaly_synced_db_common/synced_db_common_firestore.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'auto_synced_sdb.dart';

/// Synced source firestore
class AutoSynchronizedFirestoreSyncedSdbOptions
    extends AutoSynchronizedFirestoreOptionsCommon
    implements AutoSynchronizedSyncedSdbOptions {
  /// Synced db options
  final SyncedSdbOptions syncedSdbOptions;

  /// Sembast db factory
  final SdbFactory databaseFactory;

  /// Sembast db name
  final String dbName;

  /// Firestore synced db options
  AutoSynchronizedFirestoreSyncedSdbOptions({
    super.firestore,
    required this.syncedSdbOptions,
    required this.databaseFactory,
    required this.dbName,
    super.readOnly = false,
    super.retryOptions,

    /// Default ok for tests only
    super.rootDocumentPath = 'test/local',
  });
}

/// Auto synchronized firestore synced db
abstract class AutoSynchronizedFirestoreSyncedSdb
    implements AutoSynchronizedSdb, AutoSynchronizedFirestoreSyncedDbCommon {
  /// Synchronizer
  @override
  SyncedSdbSynchronizer get synchronizer;

  /// Synced db
  SyncedSdb get syncedSdb;

  /// Options
  @override
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

  /// Wait for current lazy synchronization to be done
  /// Future<void> waitSynchronized();
}

class _AutoSynchronizedFirestoreSyncedSdb
    extends
        AutoSynchronizedFirestoreSyncedDbBase<SyncedSdb, SyncedSdbSynchronizer>
    implements AutoSynchronizedFirestoreSyncedSdb {
  @override
  SyncedSdb get syncedSdb => syncedDb;

  @override
  late SdbDatabase database;
  @override
  final AutoSynchronizedFirestoreSyncedSdbOptions options;

  _AutoSynchronizedFirestoreSyncedSdb({required this.options});

  @override
  Future<SyncedSdb> openSyncedDb() async {
    var syncedSdb = SyncedSdb.openDatabase(
      options: options.syncedSdbOptions,
      databaseFactory: options.databaseFactory,
      name: options.dbName,
    );
    database = await syncedSdb.database;
    return syncedSdb;
  }

  @override
  SyncedSdbSynchronizer newSynchronizer(
    SyncedSdb syncedDb, {
    SyncedSource? source,
    SyncedSourceRead? readSource,
    required bool autoSync,
    required SyncedDbSynchronizerRetryOptions retryOptions,
  }) => SyncedSdbSynchronizer(
    db: syncedDb,
    source: source,
    readSource: readSource,
    autoSync: autoSync,
    retryOptions: retryOptions,
  );
}
