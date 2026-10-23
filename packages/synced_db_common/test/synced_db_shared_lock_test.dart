import 'dart:async';

import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

void main() {
  test('result and error', () async {
    expect(await syncedDbSharedLock('test_result', () async => 1), 1);
    await expectLater(
      syncedDbSharedLock<int>('test_error', () async => throw StateError('x')),
      throwsStateError,
    );
    // Released after an error.
    expect(await syncedDbSharedLock('test_error', () async => 2), 2);
  });

  test('one holder at a time in a browser', () async {
    var events = <String>[];
    var firstStarted = Completer<void>();
    var releaseFirst = Completer<void>();
    var first = syncedDbSharedLock('test_order', () async {
      events.add('first start');
      firstStarted.complete();
      await releaseFirst.future;
      events.add('first end');
    });
    await firstStarted.future;
    var second = syncedDbSharedLock('test_order', () async {
      events.add('second');
    });
    // Another name is not blocked.
    await syncedDbSharedLock('test_other', () async {
      events.add('other');
    });
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(events, ['first start', 'other', 'first end', 'second']);
  }, testOn: 'browser');
}
