import 'package:tekaly_stat/stat_client.dart';
import 'package:test/test.dart';

void main() {
  group('stat_event', () {
    test('unsaved events are distinct', () {
      var event1 = StatEvent(name: 'a', data: 1);
      var event2 = StatEvent(name: 'b', data: 2);
      expect(event1, isNot(event2));
      expect(event1, event1);
      expect({event1, event2}, hasLength(2));
    });
    test('saved events are equal by id', () {
      var event1 = StatEventBase(name: 'a', data: 1)..idOrNull = 'id1';
      var event2 = StatEventBase(name: 'a', data: 1)..idOrNull = 'id1';
      var event3 = StatEventBase(name: 'a', data: 1)..idOrNull = 'id2';
      var unsaved = StatEventBase(name: 'a', data: 1);
      expect(event1, event2);
      expect(event1.hashCode, event2.hashCode);
      expect(event1, isNot(event3));
      expect(event1, isNot(unsaved));
      expect(unsaved, isNot(event1));
    });
  });
}
