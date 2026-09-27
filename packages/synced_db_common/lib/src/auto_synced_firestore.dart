import 'package:meta/meta.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';

import 'synced_db_common_types.dart';
import 'synced_db_sync_status.dart';
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

  /// Wait for the first synchronization, done in this or a previous session.
  ///
  /// A failed synchronization is retried (see
  /// [AutoSynchronizedFirestoreOptionsCommon.retryOptions]), so this
  /// terminates once the source becomes reachable. It never completes while
  /// the source is unreachable on a first run: see [waitInitialSync] for a
  /// timeout and a finer policy. Throws a [StateError] when closed before.
  Future<void> initialSynchronizationDone();

  /// The synchronization status, the current one first, then its changes:
  /// never/previously/freshly synchronized, syncing, retrying...
  Stream<SyncedDbSyncStatus> onSyncStatus();

  /// Wait until the app can display the local data according to [policy]
  /// (a sync done in this or a previous session by default).
  ///
  /// Completes with the status satisfying [policy], or with the current one
  /// once closed or when [timeout] expires: the caller checks the returned
  /// status, for example to show an offline screen with a retry button
  /// ([requestSync]).
  Future<SyncedDbSyncStatus> waitInitialSync({
    SyncedDbInitialSyncPolicy policy = SyncedDbInitialSyncPolicy.any,
    Duration? timeout,
  });

  /// Trigger a synchronization now without waiting for it, cancelling a
  /// scheduled retry (retry button, network back). Its outcome shows in
  /// [onSyncStatus].
  void requestSync();

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
    var status = await waitInitialSync();
    if (!status.isInitialSyncDone) {
      throw StateError('Closed before the initial synchronization');
    }
  }

  @override
  Stream<SyncedDbSyncStatus> onSyncStatus() async* {
    await ready;
    yield* synchronizer.onSyncStatus();
  }

  @override
  Future<SyncedDbSyncStatus> waitInitialSync({
    SyncedDbInitialSyncPolicy policy = SyncedDbInitialSyncPolicy.any,
    Duration? timeout,
  }) async {
    // Opening the local database is quick, the timeout is for the sync.
    await ready;
    return await synchronizer.waitInitialSync(policy: policy, timeout: timeout);
  }

  @override
  void requestSync() {
    ready.then((_) => synchronizer.requestSync()).catchError((Object _) {});
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
