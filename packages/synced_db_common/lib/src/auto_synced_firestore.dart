import 'package:meta/meta.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';

import 'synced_db_common_types.dart';
import 'synced_db_synchronizer_common.dart';
import 'synced_db_synchronizer_retry.dart';
import 'synced_source.dart';
import 'synced_source_firestore.dart';

/// Options of an automatically synchronized firestore synced db, common to
/// the sembast and sdb implementations.
abstract class AutoSynchronizedFirestoreOptionsCommon {
  /// Firestore instance
  final Firestore firestore;

  /// Root document path
  final String rootDocumentPath;

  /// Read-only: only sync down, local changes are never pushed to firestore
  /// (a public source the user cannot write to).
  final bool readOnly;

  /// Retry strategy when a synchronization fails (the network is down...).
  /// By default, while the first synchronization is pending, every 5s during
  /// 1 minute then growing to reach 1 minute after 5 minutes of retrying;
  /// once it is done, 15s doubled on each failure up to 1 minute.
  final SyncedDbSynchronizerRetryOptions retryOptions;

  /// Firestore defaults to [Firestore.instance].
  AutoSynchronizedFirestoreOptionsCommon({
    Firestore? firestore,
    required this.rootDocumentPath,
    required this.readOnly,
    SyncedDbSynchronizerRetryOptions? retryOptions,
  }) : firestore = firestore ?? Firestore.instance,
       retryOptions = retryOptions ?? const SyncedDbSynchronizerRetryOptions();
}

/// Automatically synchronized firestore synced db, common to the sembast and
/// sdb implementations.
abstract class AutoSynchronizedFirestoreSyncedDbCommon {
  /// Options
  AutoSynchronizedFirestoreOptionsCommon get options;

  /// Synchronizer
  SyncedDbSynchronizerCommon get synchronizer;

  /// Wait for the first synchronization.
  ///
  /// A failed synchronization is retried (see
  /// [AutoSynchronizedFirestoreOptionsCommon.retryOptions]), so this
  /// terminates once the source becomes reachable, it does not wait forever
  /// when the network is down when the database is opened.
  Future<void> initialSynchronizationDone();

  /// Close the db
  Future<void> close();

  /// Synchronize
  Future<SyncedSyncStat> synchronize();

  /// Lazy synchronize if needed (timing undefined) - same as synchronize as of 2026/02/05
  Future<SyncedSyncStat> lazySynchronize();
}

/// Implementation of [AutoSynchronizedFirestoreSyncedDbCommon], the sembast
/// and sdb implementations opening their synced db and creating their
/// synchronizer.
abstract class AutoSynchronizedFirestoreSyncedDbBase<
  TSyncedDb extends SyncedDbCommon,
  TSynchronizer extends SyncedDbSynchronizerCommon
>
    implements AutoSynchronizedFirestoreSyncedDbCommon {
  /// Synced db, valid when [ready].
  late final TSyncedDb syncedDb;

  @override
  late final TSynchronizer synchronizer;

  /// Open the synced db, called once by [ready].
  @protected
  Future<TSyncedDb> openSyncedDb();

  /// Create the synchronizer, see [SyncedDbSynchronizerCommon].
  @protected
  TSynchronizer newSynchronizer(
    TSyncedDb syncedDb, {
    SyncedSource? source,
    SyncedSourceRead? readSource,
    required bool autoSync,
    required SyncedDbSynchronizerRetryOptions retryOptions,
  });

  /// Done when the synced db is opened and the synchronizer created.
  late final Future<void> ready = () async {
    syncedDb = await openSyncedDb();
    var source = SyncedSourceFirestore(
      firestore: options.firestore,
      rootPath: options.rootDocumentPath,
    );
    synchronizer = newSynchronizer(
      syncedDb,
      // Read-only: the source is only read.
      source: options.readOnly ? null : source,
      readSource: options.readOnly ? source : null,
      autoSync: true,
      retryOptions: options.retryOptions,
    );
  }();

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
