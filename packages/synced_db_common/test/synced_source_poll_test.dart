import 'dart:async';

import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

void main() {
  group('synced_source_poll', () {
    test('cancel stops the wait between two reads', () async {
      var timers = <Timer>[];
      await runZoned(
        () async {
          var source = SyncedSourceMemory();
          var info = await syncedSourceReadPollMetaInfo(
            source,
            checkDelay: const Duration(hours: 1),
          ).first;
          expect(info, isNull);
          await source.close();
          // Let the poll loop see the cancel
          await Future<void>.delayed(Duration.zero);
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            var timer = parent.createTimer(zone, duration, callback);
            if (duration >= const Duration(minutes: 1)) {
              timers.add(timer);
            }
            return timer;
          },
        ),
      );
      // A pending 1 hour wait kept the process alive after the cancel
      expect(timers.where((timer) => timer.isActive), isEmpty);
    });
  });
}
