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
    test('default delays', () {
      const options = SyncedDbSynchronizerRetryOptions();
      expect(options.enabled, isTrue);
      // Short constant delay while the first sync has not been done.
      for (var count in [1, 2, 10]) {
        expect(
          options.delayForFailureCount(count, firstSyncDone: false),
          const Duration(seconds: 5),
        );
      }
      // Then 15s, doubled on each failure, up to 1 minute.
      expect(
        options.delayForFailureCount(1, firstSyncDone: true),
        const Duration(seconds: 15),
      );
      expect(
        options.delayForFailureCount(2, firstSyncDone: true),
        const Duration(seconds: 30),
      );
      expect(
        options.delayForFailureCount(3, firstSyncDone: true),
        const Duration(minutes: 1),
      );
      expect(
        options.delayForFailureCount(100, firstSyncDone: true),
        const Duration(minutes: 1),
      );
    });

    test('custom delays', () {
      const options = SyncedDbSynchronizerRetryOptions(
        firstSyncDelay: Duration(seconds: 1),
        delay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 10),
        backoffFactor: 3,
      );
      expect(
        options.delayForFailureCount(1, firstSyncDone: false),
        const Duration(seconds: 1),
      );
      expect(
        options.delayForFailureCount(1, firstSyncDone: true),
        const Duration(seconds: 2),
      );
      expect(
        options.delayForFailureCount(2, firstSyncDone: true),
        const Duration(seconds: 6),
      );
      expect(
        options.delayForFailureCount(3, firstSyncDone: true),
        const Duration(seconds: 10),
      );
    });

    test('constant delay when there is no backoff', () {
      const options = SyncedDbSynchronizerRetryOptions(
        delay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 10),
        backoffFactor: 1,
      );
      expect(
        options.delayForFailureCount(5, firstSyncDone: true),
        const Duration(seconds: 2),
      );
    });

    test('noRetry', () {
      const options = SyncedDbSynchronizerRetryOptions.noRetry();
      expect(options.enabled, isFalse);
    });
  });
}
