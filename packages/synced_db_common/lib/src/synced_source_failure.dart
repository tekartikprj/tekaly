import 'package:meta/meta.dart';

/// A synced source operation, used to make a source fail on purpose in tests.
enum SyncedSourceOperation {
  /// `SyncedSourceRead.getMetaInfo`
  getMetaInfo,

  /// `SyncedSourceRead.getSourceRecord`
  getSourceRecord,

  /// `SyncedSourceRead.getSourceRecordList`
  getSourceRecordList,

  /// `SyncedSourceWrite.putMetaInfo`
  putMetaInfo,

  /// `SyncedSourceWrite.putSourceRecord`
  putSourceRecord,

  /// `SyncedSourceWrite.putRawRecord`
  putRawRecord,
}

/// Error thrown by default by a source failing on purpose, simulating an
/// unreachable source (network down, server error...).
class SyncedSourceFailureException implements Exception {
  /// The operation that failed, null when unknown.
  final SyncedSourceOperation? operation;

  /// Error message.
  final String message;

  /// Constructor.
  SyncedSourceFailureException({this.operation, String? message})
    : message = message ?? 'Synced source failure';

  @override
  String toString() =>
      'SyncedSourceFailureException($message'
      '${operation == null ? '' : ', ${operation!.name}'})';
}

/// Testing only: makes the operations of a synced source throw on purpose,
/// to check that a synchronizer retries.
///
/// Typically used through [SyncedSourceFailureMixin] (`SyncedSourceMemory`):
///
/// ```dart
/// var source = SyncedSourceMemory();
/// // Every operation fails for 1 second.
/// source.failureControl.fail(duration: const Duration(seconds: 1));
/// // Only the 3 next getMetaInfo calls fail, with a custom error.
/// source.failureControl.fail(
///   error: StateError('offline'),
///   count: 3,
///   operations: {SyncedSourceOperation.getMetaInfo},
/// );
/// source.failureControl.stop();
/// ```
class SyncedSourceFailureControl {
  var _armed = false;
  Object? _error;
  DateTime? _until;
  int? _remainingCount;
  Set<SyncedSourceOperation>? _operations;
  var _failedCount = 0;

  /// Number of operations failed so far (never reset by [stop]).
  int get failedCount => _failedCount;

  /// True while failures are armed (independently of the operation).
  bool get isFailing => _armed;

  /// Make the source operations fail.
  ///
  /// [error] is thrown, a [SyncedSourceFailureException] by default.
  ///
  /// Failures stop after [duration] and/or after [count] failed operations,
  /// whichever comes first. When neither is set, the source fails until
  /// [stop] is called.
  ///
  /// [operations] restricts the failure to some operations, every operation
  /// fails by default.
  void fail({
    Object? error,
    Duration? duration,
    int? count,
    Iterable<SyncedSourceOperation>? operations,
  }) {
    _armed = true;
    _error = error;
    _until = duration == null ? null : DateTime.timestamp().add(duration);
    _remainingCount = count;
    _operations = operations == null ? null : Set.of(operations);
  }

  /// Stop failing.
  void stop() {
    _armed = false;
    _error = null;
    _until = null;
    _remainingCount = null;
    _operations = null;
  }

  /// Throw the configured error when [operation] must currently fail.
  void check(SyncedSourceOperation operation) {
    if (!_shouldFail(operation)) {
      return;
    }
    _failedCount++;
    var remainingCount = _remainingCount;
    if (remainingCount != null) {
      _remainingCount = remainingCount - 1;
    }
    // The caller chooses the error, any object is allowed.
    // ignore: only_throw_errors
    throw _error ?? SyncedSourceFailureException(operation: operation);
  }

  /// Whether [operation] currently fails, disarming an expired failure.
  bool _shouldFail(SyncedSourceOperation operation) {
    if (!_armed) {
      return false;
    }
    var operations = _operations;
    if (operations != null && !operations.contains(operation)) {
      return false;
    }
    var until = _until;
    if (until != null && !DateTime.timestamp().isBefore(until)) {
      // Duration elapsed.
      stop();
      return false;
    }
    var remainingCount = _remainingCount;
    if (remainingCount != null && remainingCount <= 0) {
      stop();
      return false;
    }
    return true;
  }

  @override
  String toString() =>
      'SyncedSourceFailureControl(${_armed ? 'failing' : 'ok'}, '
      '$_failedCount failure(s))';
}

/// Adds testing failure injection to a synced source implementation.
///
/// The implementation calls [checkFailure] at the beginning of each operation.
mixin SyncedSourceFailureMixin {
  /// Testing only: make this source fail on purpose, see
  /// [SyncedSourceFailureControl].
  @visibleForTesting
  final failureControl = SyncedSourceFailureControl();

  /// Throw when [operation] is currently set to fail.
  @protected
  void checkFailure(SyncedSourceOperation operation) =>
      failureControl.check(operation);
}
