/// Retry strategy of an automatically synchronized database.
///
/// When a synchronization fails in auto sync mode (the source is unreachable,
/// the network is down...), the synchronizer schedules a new one:
/// - while the first synchronization has not succeeded yet, after
///   [firstSyncDelay] (short, the application is likely waiting on
///   `initialSynchronizationDone`) for the first [firstSyncShortDuration] of
///   retrying, the delay then growing to reach [maxDelay] after
///   [firstSyncMaxDelayDuration] of retrying,
/// - once the first synchronization is done, after [delay], doubled
///   ([backoffFactor]) on each consecutive failure up to [maxDelay].
///
/// With the default values: 5s for 1 minute, then growing up to 1 minute after
/// 5 minutes of retrying; and 15s, 30s, 1mn, 1mn... once the first
/// synchronization is done.
///
/// Everything is reset as soon as a synchronization succeeds.
class SyncedDbSynchronizerRetryOptions {
  /// Delay between 2 retries while the first synchronization has not succeeded
  /// yet (5s by default), kept during [firstSyncShortDuration].
  final Duration firstSyncDelay;

  /// How long [firstSyncDelay] is kept while the first synchronization has not
  /// succeeded (1 minute by default), the delay then grows up to [maxDelay].
  final Duration firstSyncShortDuration;

  /// Time spent retrying after which the first synchronization retries reach
  /// [maxDelay] (5 minutes by default).
  final Duration firstSyncMaxDelayDuration;

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

  /// Default retry strategy, see the class documentation.
  const SyncedDbSynchronizerRetryOptions({
    this.firstSyncDelay = const Duration(seconds: 5),
    this.firstSyncShortDuration = const Duration(minutes: 1),
    this.firstSyncMaxDelayDuration = const Duration(minutes: 5),
    this.delay = const Duration(seconds: 15),
    this.maxDelay = const Duration(minutes: 1),
    this.backoffFactor = 2,
  }) : enabled = true;

  /// Never retry a failed synchronization.
  const SyncedDbSynchronizerRetryOptions.noRetry()
    : firstSyncDelay = Duration.zero,
      firstSyncShortDuration = Duration.zero,
      firstSyncMaxDelayDuration = Duration.zero,
      delay = Duration.zero,
      maxDelay = Duration.zero,
      backoffFactor = 1,
      enabled = false;

  /// Delay before the retry following [failureCount] consecutive failures
  /// (1 for the first failure), [retryingFor] being the time elapsed since the
  /// first of those failures.
  Duration delayForFailure({
    required int failureCount,
    required Duration retryingFor,
    required bool firstSyncDone,
  }) {
    if (!firstSyncDone) {
      return _firstSyncDelayFor(retryingFor);
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

  /// [firstSyncDelay] during [firstSyncShortDuration], then growing linearly
  /// to reach [maxDelay] at [firstSyncMaxDelayDuration].
  Duration _firstSyncDelayFor(Duration retryingFor) {
    if (retryingFor < firstSyncShortDuration) {
      return firstSyncDelay;
    }
    if (firstSyncDelay >= maxDelay ||
        retryingFor >= firstSyncMaxDelayDuration) {
      return maxDelay;
    }
    var growDuration = firstSyncMaxDelayDuration - firstSyncShortDuration;
    if (growDuration <= Duration.zero) {
      return maxDelay;
    }
    var ratio =
        (retryingFor - firstSyncShortDuration).inMicroseconds /
        growDuration.inMicroseconds;
    return firstSyncDelay + (maxDelay - firstSyncDelay) * ratio;
  }

  @override
  String toString() => enabled
      ? 'SyncedDbSynchronizerRetryOptions(firstSync: $firstSyncDelay for '
            '$firstSyncShortDuration to $maxDelay after '
            '$firstSyncMaxDelayDuration, then $delay to $maxDelay '
            'x$backoffFactor)'
      : 'SyncedDbSynchronizerRetryOptions.noRetry()';
}
