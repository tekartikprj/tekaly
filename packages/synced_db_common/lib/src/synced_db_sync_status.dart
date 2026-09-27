/// How fresh the local data is, regarding the synchronization with the
/// source.
enum SyncedDbInitialSync {
  /// Local sync meta info not read yet (a few ms after opening).
  unknown,

  /// Never synchronized: the local database only holds local changes, if any.
  never,

  /// Synchronized in a previous session, not yet in this one: the local data
  /// may be stale.
  previousSession,

  /// A sync down succeeded in this session.
  thisSession,
}

/// What the synchronizer is doing.
enum SyncedDbSyncActivity {
  /// Nothing running, the last synchronization (if any) succeeded.
  idle,

  /// A synchronization is running.
  syncing,

  /// The last synchronization failed with a transient error (network,
  /// offline...), a retry is scheduled.
  retryScheduled,

  /// The last synchronization failed with a permanent error (no access...)
  /// or retrying is off (no auto sync, no retry options): only a new trigger
  /// or a slow retry (`SyncedDbSynchronizerRetryOptions.permanentErrorDelay`)
  /// tries again.
  failed,

  /// The synchronizer was closed.
  closed,
}

/// What an app waits for before displaying the local data, see
/// `waitInitialSync`.
enum SyncedDbInitialSyncPolicy {
  /// Show the local data right away (local first).
  none,

  /// Wait for a synchronization done in this or a previous session.
  any,

  /// Wait for a synchronization done in this session (fresh data).
  thisSession,
}

/// Synchronization status of a synced db, see `onSyncStatus`.
class SyncedDbSyncStatus {
  /// How fresh the local data is.
  final SyncedDbInitialSync initialSync;

  /// What the synchronizer is doing.
  final SyncedDbSyncActivity activity;

  /// True for a read-only synchronizer (sync down only).
  final bool readOnly;

  /// Local changes not pushed yet (always false when read-only, local
  /// changes being never pushed).
  final bool hasLocalChanges;

  /// Local time of the last successful sync down in this session.
  final DateTime? lastSyncTime;

  /// Error of the last synchronization, null once one succeeds.
  final Object? lastError;

  /// Number of consecutive failed synchronizations.
  final int failureCount;

  /// Time of the first of the current consecutive failures.
  final DateTime? retryingSince;

  /// Time of the next scheduled retry, if any.
  final DateTime? nextRetryTime;

  /// Status snapshot.
  const SyncedDbSyncStatus({
    required this.initialSync,
    required this.activity,
    this.readOnly = false,
    this.hasLocalChanges = false,
    this.lastSyncTime,
    this.lastError,
    this.failureCount = 0,
    this.retryingSince,
    this.nextRetryTime,
  });

  /// True once the local database was synchronized, in this or a previous
  /// session.
  bool get isInitialSyncDone =>
      initialSync == SyncedDbInitialSync.previousSession ||
      initialSync == SyncedDbInitialSync.thisSession;

  /// True once closed.
  bool get isClosed => activity == SyncedDbSyncActivity.closed;

  /// True when [policy] is satisfied: the app can display the local data.
  bool satisfies(SyncedDbInitialSyncPolicy policy) {
    switch (policy) {
      case SyncedDbInitialSyncPolicy.none:
        return true;
      case SyncedDbInitialSyncPolicy.any:
        return isInitialSyncDone;
      case SyncedDbInitialSyncPolicy.thisSession:
        return initialSync == SyncedDbInitialSync.thisSession;
    }
  }

  @override
  int get hashCode => Object.hash(
    initialSync,
    activity,
    readOnly,
    hasLocalChanges,
    lastSyncTime,
    lastError,
    failureCount,
    retryingSince,
    nextRetryTime,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncedDbSyncStatus &&
      other.initialSync == initialSync &&
      other.activity == activity &&
      other.readOnly == readOnly &&
      other.hasLocalChanges == hasLocalChanges &&
      other.lastSyncTime == lastSyncTime &&
      other.lastError == lastError &&
      other.failureCount == failureCount &&
      other.retryingSince == retryingSince &&
      other.nextRetryTime == nextRetryTime;

  @override
  String toString() =>
      'SyncedDbSyncStatus(${initialSync.name}, '
      '${activity.name}'
      '${readOnly ? ', readOnly' : ''}'
      '${hasLocalChanges ? ', hasLocalChanges' : ''}'
      '${lastSyncTime == null ? '' : ', lastSync: $lastSyncTime'}'
      '${lastError == null ? '' : ', error: $lastError'}'
      '${failureCount == 0 ? '' : ', failures: $failureCount'}'
      '${nextRetryTime == null ? '' : ', nextRetry: $nextRetryTime'})';
}
