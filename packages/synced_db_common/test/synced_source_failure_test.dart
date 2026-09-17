import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

void main() {
  group('synced_source_failure', () {
    test('not failing by default', () async {
      var source = SyncedSourceMemory();
      expect(source.failureControl.isFailing, isFalse);
      expect(await source.getMetaInfo(), isNull);
      expect(source.failureControl.failedCount, 0);
    });

    test('fail until stopped', () async {
      var source = SyncedSourceMemory();
      source.failureControl.fail();
      expect(source.failureControl.isFailing, isTrue);
      await expectLater(
        source.getMetaInfo(),
        throwsA(isA<SyncedSourceFailureException>()),
      );
      await expectLater(
        source.getSourceRecordList(),
        throwsA(isA<SyncedSourceFailureException>()),
      );
      source.failureControl.stop();
      expect(await source.getMetaInfo(), isNull);
      expect(source.failureControl.failedCount, 2);
    });

    test('fail with a given error', () async {
      var source = SyncedSourceMemory();
      var error = StateError('offline');
      source.failureControl.fail(error: error);
      await expectLater(source.getMetaInfo(), throwsA(same(error)));
    });

    test('fail for a duration', () async {
      var source = SyncedSourceMemory();
      source.failureControl.fail(duration: const Duration(milliseconds: 100));
      await expectLater(source.getMetaInfo(), throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await source.getMetaInfo(), isNull);
      expect(source.failureControl.isFailing, isFalse);
    });

    test('fail a given count of times', () async {
      var source = SyncedSourceMemory();
      source.failureControl.fail(count: 2);
      await expectLater(source.getMetaInfo(), throwsA(anything));
      await expectLater(source.getMetaInfo(), throwsA(anything));
      expect(await source.getMetaInfo(), isNull);
      expect(source.failureControl.failedCount, 2);
    });

    test('fail some operations only', () async {
      var source = SyncedSourceMemory();
      source.failureControl.fail(
        operations: {SyncedSourceOperation.getMetaInfo},
      );
      await expectLater(source.getMetaInfo(), throwsA(anything));
      // Writing still works.
      var record = await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'entity'
            ..key.v = 'a1'
            ..value.v = {'name': 'test'}),
      );
      expect(record.syncChangeId.v, 1);
      await expectLater(source.getMetaInfo(), throwsA(anything));
    });

    test('a failing source does not break the meta info polling', () async {
      var source = SyncedSourceMemory();
      source.failureControl.fail(count: 1);
      // The first read fails and is emitted as an error, the next one (after
      // checkDelay) succeeds.
      var events = await source
          .onMetaInfo(checkDelay: const Duration(milliseconds: 10))
          .map<Object?>((event) => event)
          .handleError((Object e) {})
          .take(1)
          .toList();
      expect(events, [null]);
      expect(source.failureControl.failedCount, 1);
    });
  });

  group('synced_db_synchronizer_retry_options', () {
    const options = SyncedDbSynchronizerRetryOptions();

    Duration firstSyncDelay(Duration retryingFor) => options.delayForFailure(
      failureCount: 1,
      retryingFor: retryingFor,
      firstSyncDone: false,
    );
    Duration delayAfterFailures(int failureCount) => options.delayForFailure(
      failureCount: failureCount,
      retryingFor: Duration.zero,
      firstSyncDone: true,
    );

    test('default delays while the first sync is pending', () {
      expect(options.enabled, isTrue);
      // Short delay, kept during the first minute of retrying.
      expect(firstSyncDelay(Duration.zero), const Duration(seconds: 5));
      expect(
        firstSyncDelay(const Duration(seconds: 59)),
        const Duration(seconds: 5),
      );
      // Then growing to reach the 1 minute maximum after 5 minutes.
      expect(
        firstSyncDelay(const Duration(minutes: 1)),
        const Duration(seconds: 5),
      );
      expect(
        firstSyncDelay(const Duration(minutes: 2)),
        const Duration(seconds: 5) + const Duration(seconds: 55) * 0.25,
      );
      expect(
        firstSyncDelay(const Duration(minutes: 3)),
        const Duration(seconds: 5) + const Duration(seconds: 55) * 0.5,
      );
      expect(firstSyncDelay(const Duration(minutes: 5)), options.maxDelay);
      expect(firstSyncDelay(const Duration(hours: 1)), options.maxDelay);
      // The delay never goes above the maximum.
      for (var minutes in [0, 1, 2, 3, 4, 5, 60]) {
        expect(
          firstSyncDelay(Duration(minutes: minutes)),
          lessThanOrEqualTo(options.maxDelay),
        );
      }
    });

    test('default delays once the first sync is done', () {
      // 15s, doubled on each failure, up to 1 minute.
      expect(delayAfterFailures(1), const Duration(seconds: 15));
      expect(delayAfterFailures(2), const Duration(seconds: 30));
      expect(delayAfterFailures(3), const Duration(minutes: 1));
      expect(delayAfterFailures(100), const Duration(minutes: 1));
    });

    test('custom delays', () {
      const options = SyncedDbSynchronizerRetryOptions(
        firstSyncDelay: Duration(seconds: 1),
        firstSyncShortDuration: Duration(seconds: 10),
        firstSyncMaxDelayDuration: Duration(seconds: 20),
        delay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 11),
        backoffFactor: 3,
      );
      Duration firstSync(Duration retryingFor) => options.delayForFailure(
        failureCount: 1,
        retryingFor: retryingFor,
        firstSyncDone: false,
      );
      Duration done(int failureCount) => options.delayForFailure(
        failureCount: failureCount,
        retryingFor: Duration.zero,
        firstSyncDone: true,
      );
      expect(firstSync(Duration.zero), const Duration(seconds: 1));
      expect(firstSync(const Duration(seconds: 9)), const Duration(seconds: 1));
      expect(
        firstSync(const Duration(seconds: 15)),
        const Duration(seconds: 6),
      );
      expect(
        firstSync(const Duration(seconds: 20)),
        const Duration(seconds: 11),
      );
      expect(
        firstSync(const Duration(minutes: 1)),
        const Duration(seconds: 11),
      );
      expect(done(1), const Duration(seconds: 2));
      expect(done(2), const Duration(seconds: 6));
      expect(done(3), const Duration(seconds: 11));
    });

    test('constant delay when there is no backoff', () {
      const options = SyncedDbSynchronizerRetryOptions(
        delay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 10),
        backoffFactor: 1,
      );
      expect(
        options.delayForFailure(
          failureCount: 5,
          retryingFor: Duration.zero,
          firstSyncDone: true,
        ),
        const Duration(seconds: 2),
      );
    });

    test('noRetry', () {
      const options = SyncedDbSynchronizerRetryOptions.noRetry();
      expect(options.enabled, isFalse);
    });
  });
}
