// The failure injection and the retry counters are test only members.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

/// Short delays, the tests must not wait for the default 5s/15s.
const _fastRetryOptions = SyncedDbSynchronizerRetryOptions(
  firstSyncDelay: Duration(milliseconds: 20),
  delay: Duration(milliseconds: 20),
  maxDelay: Duration(milliseconds: 40),
);

const _storeName = 'entity';

final _sdbStoreRef = SdbStoreRef<String, SdbModel>(_storeName);
final _sdbOptions = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [_sdbStoreRef.schema(), ...syncedSdbMetaSchema.stores],
    ),
  ),
);

/// A source that never reports its meta info and never fails either (an
/// unreachable source that just hangs), everything else works.
///
/// Nothing then ever reaches the synchronizer auto sync stream: only the first
/// sync watchdog can trigger the initial synchronization.
class _SilentMetaInfoSource
    with SyncedSourceDefaultMixin
    implements SyncedSource {
  final SyncedSource inner;
  final _metaInfoController = StreamController<CvMetaInfo?>();

  _SilentMetaInfoSource(this.inner) {
    initBuilders();
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) =>
      _metaInfoController.stream;

  @override
  Future<CvMetaInfo?> getMetaInfo() => inner.getMetaInfo();

  @override
  Future<CvMetaInfo> putMetaInfo(CvMetaInfo info) async =>
      (await inner.putMetaInfo(info))!;

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef) =>
      inner.getSourceRecord(sourceRef);

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) => inner.getSourceRecordList(
    afterChangeId: afterChangeId,
    limit: limit,
    includeDeleted: includeDeleted,
  );

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record) =>
      inner.putSourceRecord(record);

  @override
  Future<void> putRawRecord(CvSyncedSourceRecord record) =>
      inner.putRawRecord(record);

  @override
  Future<void> close() async {
    await _metaInfoController.close();
    await inner.close();
  }
}

/// A local database and its synchronizer, for one implementation.
class _SyncContext {
  final SyncedDbSynchronizerCommon synchronizer;

  /// Waits for the first synchronization of the local database.
  final Future<void> Function() initialSynchronizationDone;

  /// Closes the synchronizer then the database.
  final Future<void> Function() close;

  _SyncContext({
    required this.synchronizer,
    required this.initialSynchronizationDone,
    required this.close,
  });
}

/// One synchronizer implementation under test.
class _Implementation {
  final String name;

  /// Opens the local database and its synchronizer on [source].
  final Future<_SyncContext> Function(
    SyncedSource source, {
    required bool autoSync,
    SyncedDbSynchronizerRetryOptions? retryOptions,
  })
  open;

  _Implementation({required this.name, required this.open});
}

final _implementations = [
  _Implementation(
    name: 'sembast',
    open: (source, {required autoSync, retryOptions}) async {
      var syncedDb = SyncedDb.newInMemory(syncedStoreNames: [_storeName]);
      await syncedDb.database;
      var synchronizer = SyncedDbSynchronizer(
        db: syncedDb,
        source: source,
        autoSync: autoSync,
        retryOptions: retryOptions,
      );
      return _SyncContext(
        synchronizer: synchronizer,
        initialSynchronizationDone: syncedDb.initialSynchronizationDone,
        close: () async {
          await synchronizer.close();
          await syncedDb.close();
        },
      );
    },
  ),
  _Implementation(
    name: 'sdb',
    open: (source, {required autoSync, retryOptions}) async {
      var syncedSdb = SyncedSdb.newInMemory(options: _sdbOptions);
      await syncedSdb.database;
      var synchronizer = SyncedSdbSynchronizer(
        db: syncedSdb,
        source: source,
        autoSync: autoSync,
        retryOptions: retryOptions,
      );
      return _SyncContext(
        synchronizer: synchronizer,
        initialSynchronizationDone: syncedSdb.initialSynchronizationDone,
        close: () async {
          await synchronizer.close();
          await syncedSdb.close();
        },
      );
    },
  ),
];

void main() {
  for (var implementation in _implementations) {
    group('synced_db_synchronizer_retry_${implementation.name}', () {
      late SyncedSourceMemory source;
      late _SyncContext context;

      Future<void> open({
        bool autoSync = true,
        SyncedDbSynchronizerRetryOptions? retryOptions = _fastRetryOptions,
      }) async {
        context = await implementation.open(
          source,
          autoSync: autoSync,
          retryOptions: retryOptions,
        );
      }

      setUp(() async {
        source = SyncedSourceMemory();
      });

      tearDown(() async {
        await context.close();
        await source.close();
      });

      test('a failing sync is retried until the source is back', () async {
        // The source is unreachable when the database is opened.
        source.failureControl.fail();
        await open();

        // Nothing is synchronized, but the synchronizer keeps trying.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(context.synchronizer.isFirstSyncDone, isFalse);
        expect(
          context.synchronizer.consecutiveSyncFailureCount,
          greaterThan(1),
          reason: 'the sync must have been retried several times',
        );
        expect(context.synchronizer.hasPendingSyncRetry, isTrue);

        // The source is reachable again, a retry eventually succeeds.
        source.failureControl.stop();
        await context.synchronizer.firstSyncDownDone().timeout(
          const Duration(seconds: 5),
        );
        expect(context.synchronizer.isFirstSyncDone, isTrue);

        // A completed synchronization clears the failure state.
        await context.synchronizer.sync();
        expect(context.synchronizer.consecutiveSyncFailureCount, 0);
        expect(context.synchronizer.hasPendingSyncRetry, isFalse);
      });

      test(
        'initialSynchronizationDone terminates once the source is back',
        () async {
          source.failureControl.fail();
          await open();

          var done = false;
          var future = context.initialSynchronizationDone().then(
            (_) => done = true,
          );

          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(
            done,
            isFalse,
            reason: 'the first sync cannot be done while the source fails',
          );

          source.failureControl.stop();
          await future.timeout(const Duration(seconds: 5));
          expect(done, isTrue);
        },
      );

      test('the retry delay grows once the first sync is done', () async {
        await open();
        await context.synchronizer.firstSyncDownDone().timeout(
          const Duration(seconds: 5),
        );

        // Now that the first sync is done, the longer delays apply.
        expect(
          context.synchronizer.retryOptions.delayForFailureCount(
            1,
            firstSyncDone: true,
          ),
          _fastRetryOptions.delay,
        );
        expect(
          context.synchronizer.retryOptions.delayForFailureCount(
            3,
            firstSyncDone: true,
          ),
          _fastRetryOptions.maxDelay,
        );

        // A failure after the first sync is reported and retried.
        var errorFuture = context.synchronizer.onSyncError().first;
        source.failureControl.fail(count: 2);
        await expectLater(
          Future<Object?>.value(context.synchronizer.sync()),
          throwsA(anything),
        );
        expect(await errorFuture.timeout(const Duration(seconds: 5)), anything);
        expect(context.synchronizer.consecutiveSyncFailureCount, 1);
        expect(context.synchronizer.hasPendingSyncRetry, isTrue);
      });

      test('no retry with SyncedDbSynchronizerRetryOptions.noRetry', () async {
        source.failureControl.fail();
        await open(
          retryOptions: const SyncedDbSynchronizerRetryOptions.noRetry(),
        );

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(context.synchronizer.hasPendingSyncRetry, isFalse);
        expect(context.synchronizer.isFirstSyncDone, isFalse);
      });

      test('the first sync watchdog syncs a silent source', () async {
        // The source never reports its meta info: without the watchdog the
        // first synchronization would never be triggered.
        context = await implementation.open(
          _SilentMetaInfoSource(source),
          autoSync: true,
          retryOptions: _fastRetryOptions,
        );
        await context.synchronizer.firstSyncDownDone().timeout(
          const Duration(seconds: 5),
        );
        expect(context.synchronizer.consecutiveSyncFailureCount, 0);
      });

      test('no retry scheduled when auto sync is off', () async {
        source.failureControl.fail();
        await open(autoSync: false);

        await expectLater(
          Future<Object?>.value(context.synchronizer.sync()),
          throwsA(anything),
        );
        expect(context.synchronizer.consecutiveSyncFailureCount, 1);
        expect(context.synchronizer.hasPendingSyncRetry, isFalse);
      });
    });
  }
}
