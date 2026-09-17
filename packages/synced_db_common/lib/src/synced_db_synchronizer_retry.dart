/// Retry strategy of an automatically synchronized database.
///
/// When a synchronization fails in auto sync mode (the source is unreachable,
/// the network is down...), the synchronizer schedules a new one:
/// - while the first synchronization has not succeeded yet, after
///   [firstSyncDelay] (short, the application is likely waiting on
///   `initialSynchronizationDone`),
/// - once the first synchronization is done, after [delay], doubled
///   ([backoffFactor]) on each consecutive failure up to [maxDelay].
///
/// The delay is reset as soon as a synchronization succeeds.
class SyncedDbSynchronizerRetryOptions {
  /// Delay before retrying while the first synchronization has not succeeded
  /// yet (5s by default, no backoff).
  final Duration firstSyncDelay;

  /// Delay before the first retry once the first synchronization is done
  /// (15s by default).
  final Duration delay;

  /// Maximum delay between 2 retries (1 minute by default).
  final Duration maxDelay;

  /// Factor applied to [delay] on each consecutive failure (2 by default),
  /// 1 or less for a constant [delay].
  final double backoffFactor;

  /// False for [SyncedDbSynchronizerRetryOptions.noRetry], a failed
  /// synchronization is then never retried.
  final bool enabled;

  /// Default retry strategy (5s while the first sync is pending, then 15s,
  /// 30s, 1mn, 1mn...).
  const SyncedDbSynchronizerRetryOptions({
    this.firstSyncDelay = const Duration(seconds: 5),
    this.delay = const Duration(seconds: 15),
    this.maxDelay = const Duration(minutes: 1),
    this.backoffFactor = 2,
  }) : enabled = true;

  /// Never retry a failed synchronization.
  const SyncedDbSynchronizerRetryOptions.noRetry()
    : firstSyncDelay = Duration.zero,
      delay = Duration.zero,
      maxDelay = Duration.zero,
      backoffFactor = 1,
      enabled = false;

  /// Delay before the retry following [failureCount] consecutive failures
  /// (1 for the first failure).
  Duration delayForFailureCount(
    int failureCount, {
    required bool firstSyncDone,
  }) {
    if (!firstSyncDone) {
      return firstSyncDelay;
    }
    if (delay >= maxDelay || backoffFactor <= 1) {
      return delay > maxDelay ? maxDelay : delay;
    }
    var result = delay;
    for (var i = 1; i < failureCount; i++) {
      result = result * backoffFactor;
      if (result >= maxDelay) {
        return maxDelay;
      }
    }
    return result;
  }

  @override
  String toString() => enabled
      ? 'SyncedDbSynchronizerRetryOptions(firstSync: $firstSyncDelay, '
            '$delay to $maxDelay, x$backoffFactor)'
      : 'SyncedDbSynchronizerRetryOptions.noRetry()';
}
