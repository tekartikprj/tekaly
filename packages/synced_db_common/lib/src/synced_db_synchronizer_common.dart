import 'dart:async';

import 'package:cv/cv.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tekartik_app_common_utils/single_flight.dart';

import 'model/db_sync_common.dart';
import 'model/source_meta_info.dart';
import 'model/source_record.dart';
import 'synced_db_common_types.dart';
import 'synced_db_synchronizer_retry.dart';
import 'synced_source.dart';

var _debugSyncedSync = false;

/// Debug Synced sync
bool get debugSyncedSync => _debugSyncedSync;

@Deprecated('Debug Synced sync')
set debugSyncedSync(bool debugSyncedSync) => _debugSyncedSync = debugSyncedSync;

/// Debug Synced sync (dev only)
@doNotSubmit
set debugSyncedDbSynchronizer(bool debugSyncedSync) =>
    _debugSyncedSync = debugSyncedSync;

/// Synced sync stat
class SyncedSyncStat {
  /// Local created count
  int localCreatedCount;

  /// Remote updated count
  int remoteUpdatedCount;

  /// Local updated count
  int localUpdatedCount;

  /// Remote updated count
  int remoteCreatedCount;

  /// Remote deleted count
  int remoteDeletedCount;

  /// Local deleted count
  int localDeletedCount;

  /// No action done
  final bool notExecuted;

  /// Default constructor
  SyncedSyncStat({
    this.notExecuted = false,

    this.localCreatedCount = 0,
    this.localUpdatedCount = 0,
    this.localDeletedCount = 0,
    this.remoteCreatedCount = 0,
    this.remoteUpdatedCount = 0,
    this.remoteDeletedCount = 0,
  });

  @override
  int get hashCode =>
      localUpdatedCount +
      localDeletedCount +
      localCreatedCount +
      remoteUpdatedCount +
      remoteDeletedCount +
      remoteCreatedCount;

  /// Modify this
  void add(SyncedSyncStat other) {
    localCreatedCount += other.localCreatedCount;
    localUpdatedCount += other.localUpdatedCount;
    localDeletedCount += other.localDeletedCount;
    remoteCreatedCount += other.remoteCreatedCount;
    remoteUpdatedCount += other.remoteUpdatedCount;
    remoteDeletedCount += other.remoteDeletedCount;
  }

  @override
  bool operator ==(Object other) {
    if (other is SyncedSyncStat) {
      if (other.localCreatedCount != localCreatedCount) {
        return false;
      }
      if (other.remoteCreatedCount != remoteCreatedCount) {
        return false;
      }

      if (other.localUpdatedCount != localUpdatedCount) {
        return false;
      }
      if (other.remoteUpdatedCount != remoteUpdatedCount) {
        return false;
      }
      if (other.remoteDeletedCount != remoteDeletedCount) {
        return false;
      }
      if (other.localDeletedCount != localDeletedCount) {
        return false;
      }
      return true;
    }
    return super == other;
  }

  @override
  String toString() {
    var map = asModel({
      if (localCreatedCount > 0) 'localCreatedCount': localCreatedCount,
      if (localUpdatedCount > 0) 'localUpdatedCount': localUpdatedCount,
      if (localDeletedCount > 0) 'localDeletedCount': localDeletedCount,
      if (remoteCreatedCount > 0) 'remoteCreatedCount': remoteCreatedCount,
      if (remoteUpdatedCount > 0) 'remoteUpdatedCount': remoteUpdatedCount,
      if (remoteDeletedCount > 0) 'remoteDeletedCount': remoteDeletedCount,
    });
    return 'SyncedSyncStat($map)';
  }
}

/// Synced sync source record (a source record and its local sync record).
class SyncedSyncSourceRecordCommon {
  /// Source record
  CvSyncedSourceRecord? sourceRecord;

  /// Sync record common
  DbSyncRecordCommon? syncRecordCommon;

  /// Has sync id
  bool get hasSyncId => syncRecordCommon?.syncId.v != null;

  /// Is new local record
  bool get isNewLocalRecord => !hasSyncId;
}

/// Synced db synchronizer base class, shared by the sembast and sdb
/// implementations.
abstract class SyncedDbSynchronizerCommon {
  /// Sync subject
  final _onSyncedSubject = StreamController<SyncedSyncStat>.broadcast();

  /// On synced stream
  Stream<SyncedSyncStat> onSynced() => _onSyncedSubject.stream;

  /// The source records and meta info are read from (sync down).
  final SyncedSourceRead readSource;

  /// The source local changes are pushed to (sync up), null for a read-only
  /// synchronizer (local changes are then never pushed and stay dirty).
  final SyncedSourceWrite? writeSource;

  /// The read-write source being synchronized, when a single [SyncedSource]
  /// was given, null for a read-only or hybrid (different read and write
  /// sources) synchronizer.
  SyncedSource? get source {
    var readSource = this.readSource;
    if (readSource is SyncedSource && identical(readSource, writeSource)) {
      return readSource;
    }
    return null;
  }

  /// True when no write source is set: local changes are never pushed.
  bool get isReadOnly => writeSource == null;

  /// Default to 10 up
  int? stepLimitUp;

  /// Default to 100 down
  int? stepLimitDown;

  /// Sync lock
  final syncLock = Lock();

  /// Constructor.
  ///
  /// Either a read-write [source], or a [readSource] and an optional
  /// [writeSource] must be given:
  /// - [source] only: regular read-write synchronization.
  /// - [readSource] only: read-only synchronization (sync down only).
  /// - [readSource] and [writeSource]: hybrid, for example read from firestore
  ///   and write through an api.
  /// [retryOptions] only applies in [autoSync] mode, see
  /// [SyncedDbSynchronizerRetryOptions].
  SyncedDbSynchronizerCommon({
    SyncedSource? source,
    SyncedSourceRead? readSource,
    SyncedSourceWrite? writeSource,
    this.autoSync = false,
    SyncedDbSynchronizerRetryOptions? retryOptions,
    required SyncedDbCommon db,
  }) : readSource =
           readSource ??
           source ??
           (throw ArgumentError('source or readSource must be set')),
       writeSource = writeSource ?? source,
       retryOptions =
           retryOptions ?? const SyncedDbSynchronizerRetryOptions(),
       dbCommon = db;

  /// Db common
  final SyncedDbCommon dbCommon;

  /// Auto sync
  final bool autoSync;

  /// Retry strategy used in [autoSync] mode when a synchronization fails.
  final SyncedDbSynchronizerRetryOptions retryOptions;

  final _onSyncErrorSubject = StreamController<Object>.broadcast();

  /// Errors of the synchronizations triggered through [sync] (a failing
  /// source, the network being down...). In [autoSync] mode a new
  /// synchronization is scheduled after each error, see [retryOptions].
  Stream<Object> onSyncError() => _onSyncErrorSubject.stream;

  final _firstSyncDoneCompleter = Completer<void>.sync();

  /// Done when the first sync down is done (could take a while the first time
  /// if offline, it is retried in [autoSync] mode).
  Future<void> firstSyncDownDone() => _firstSyncDoneCompleter.future;

  /// True when the first sync down has been done.
  bool get isFirstSyncDone => _firstSyncDoneCompleter.isCompleted;

  /// Called by the implementations at the end of a successful sync down.
  @protected
  void markFirstSyncDone() {
    if (!_firstSyncDoneCompleter.isCompleted) {
      _firstSyncDoneCompleter.complete();
    }
  }

  var _closed = false;

  /// True once [closeCommon] was called (closing or closed).
  bool get closed => _closed;

  Timer? _retryTimer;
  Timer? _firstSyncTimer;
  var _consecutiveSyncFailureCount = 0;

  /// Number of consecutive failed synchronizations, 0 when the last one
  /// succeeded.
  @visibleForTesting
  int get consecutiveSyncFailureCount => _consecutiveSyncFailureCount;

  /// True when a synchronization retry is scheduled.
  @visibleForTesting
  bool get hasPendingSyncRetry => _retryTimer?.isActive ?? false;

  /// The synchronization triggered automatically, overriden to be the lazy
  /// one in the implementations.
  @protected
  FutureOr<SyncedSyncStat> autoSyncAction() => sync();

  /// Trigger an automatic synchronization nobody awaits: its error is
  /// reported through [onSyncError] and retried rather than left as an
  /// unhandled one (a source that became unreachable, a database closed while
  /// synchronizing).
  @protected
  void triggerAutoSync() {
    if (_closed) {
      return;
    }
    void handleError(Object e) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('auto sync error: $e');
      }
    }

    try {
      var result = autoSyncAction();
      if (result is Future<SyncedSyncStat>) {
        unawaited(
          result.catchError((Object e) {
            handleError(e);
            return SyncedSyncStat(notExecuted: true);
          }),
        );
      }
    } catch (e) {
      // Typically closed while triggering.
      handleError(e);
    }
  }

  /// Called by the implementations when the source meta info stream reports
  /// an error in [autoSync] mode (the source is unreachable): counted as a
  /// failed synchronization so that a new one is scheduled, see
  /// [retryOptions].
  @protected
  void handleAutoSyncSourceError(Object error) {
    if (!autoSync || _closed) {
      return;
    }
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('auto sync source error: $error');
    }
    _handleSyncFailure(error);
  }

  /// Make sure a first synchronization is attempted in [autoSync] mode even
  /// when the source never reports its meta info nor fails (an unreachable
  /// source that just hangs): one is triggered after
  /// [SyncedDbSynchronizerRetryOptions.firstSyncDelay] when none happened yet.
  ///
  /// Called by the implementations when auto sync is set up.
  @protected
  void startFirstSyncWatchdog() {
    if (!autoSync || !retryOptions.enabled || _closed) {
      return;
    }
    _firstSyncTimer?.cancel();
    _firstSyncTimer = Timer(retryOptions.firstSyncDelay, () {
      _firstSyncTimer = null;
      if (_closed || isFirstSyncDone || hasPendingSyncRetry) {
        return;
      }
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('first sync watchdog');
      }
      triggerAutoSync();
    });
  }

  void _handleSyncSuccess() {
    _consecutiveSyncFailureCount = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
    _firstSyncTimer?.cancel();
    _firstSyncTimer = null;
  }

  void _handleSyncFailure(Object error) {
    _consecutiveSyncFailureCount++;
    if (!_onSyncErrorSubject.isClosed) {
      _onSyncErrorSubject.add(error);
    }
    _scheduleSyncRetry();
  }

  /// Schedule a new synchronization after a failed one, the delay growing
  /// with the number of consecutive failures once the first sync is done.
  void _scheduleSyncRetry() {
    if (!autoSync || !retryOptions.enabled || _closed) {
      return;
    }
    var delay = retryOptions.delayForFailureCount(
      _consecutiveSyncFailureCount,
      firstSyncDone: isFirstSyncDone,
    );
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('sync retry #$_consecutiveSyncFailureCount in $delay');
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      triggerAutoSync();
    });
  }

  /// Common close, cancelling any pending retry. Called by the
  /// implementations [close].
  @protected
  void closeCommon() {
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _firstSyncTimer?.cancel();
    _firstSyncTimer = null;
  }

  /// Sync down
  Future<SyncedSyncStat> doSyncDown();

  /// Sync down
  Future<SyncedSyncStat> syncDown() async {
    return syncLock.synchronized(() {
      return doSyncDown();
    });
  }

  /// Sync up
  Future<SyncedSyncStat> doSyncUp({bool fullSync = false});

  /// Sync dirty records up
  Future<SyncedSyncStat> syncUp({bool fullSync = false}) async {
    return syncLock.synchronized(() {
      return doSyncUp(fullSync: fullSync);
    });
  }

  /// Sync up and down
  Future<SyncedSyncStat> doSync() async {
    var stat = SyncedSyncStat();
    var upStat = await doSyncUp();
    stat.add(upStat);
    var downStat = await doSyncDown();
    stat.add(downStat);
    if (debugSyncedSync) {
      // ignore: avoid_print
      print('_end sync $stat');
    }
    _onSyncedSubject.add(stat);
    return stat;
  }

  late final _singleFlight = SingleFlight<SyncedSyncStat>(() async {
    return await syncLock.synchronized(() async {
      try {
        var stat = await doSync();
        _handleSyncSuccess();
        return stat;
      } catch (e, st) {
        if (debugSyncedSync) {
          // ignore: avoid_print
          print('sync error $e $st');
        }
        _handleSyncFailure(e);
        rethrow;
      }
    });
  });

  /// Sync up and down
  FutureOr<SyncedSyncStat> sync() {
    return _singleFlight.run();
  }

  /// Wait for the current sync (if any) to terminate.
  @protected
  Future<void> waitSync() => _singleFlight.wait();

  /// Close the single flight, waiting for the current sync to terminate.
  @protected
  Future<void> closeSingleFlight() => _singleFlight.close();

  CvMetaInfo? _lastSyncMetaInfo;

  /// Last source meta info
  CvMetaInfo? get lastSyncMetaInfo => _lastSyncMetaInfo;

  /// Use it internally to cache the source meta info.
  Future<CvMetaInfo?> getSourceMetaInfo() async {
    var sourceMetaInfo = await readSource.getMetaInfo();
    _lastSyncMetaInfo = sourceMetaInfo;
    return lastSyncMetaInfo;
  }

  /// Closing
  void dispose() {
    closeCommon();
    _onSyncedSubject.close();
    _onSyncErrorSubject.close();
  }
}
