import 'package:tekaly_stat/stat_firebase.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:tekartik_firebase_local/firebase_local.dart';
import 'package:tekartik_firebase_storage_fs/storage_fs.dart';
import 'package:test/test.dart';

Future<void> main() async {
  group('stat_storage', () {
    late StatClient client;
    setUp(() async {
      var app = newFirebaseAppLocal();
      var fbFirestore = newFirestoreServiceMemory().firestore(app);
      var fbStorage = newStorageServiceMemory().storage(app);
      var storageFirebase = StatStorageFirebase(
          options: StatStorageOptionsFirebase(
              storage: fbStorage,
              firestore: fbFirestore,
              fsRootDoc: fbFirestore.collection('tp').doc('test')));
      client =
          StatClientFirebase(storage: storageFirebase, clientId: 'my_client');
    });
    tearDown(() async {
      await client.close();
    });

    test('add/get', () async {
      var statEvent = await client.addEvent(StatEvent(name: 'test', data: 1));
      expect(statEvent.timestamp, isA<DateTime>());
      expect(statEvent.name, 'test');
      expect(statEvent.data, 1);
      var readStatEvent = await client.getEvent(statEvent.id);
      expect(readStatEvent, statEvent);
    });
    test('get list', () async {
      var event1 = await client.addEvent(
          StatEvent(timestamp: DateTime(2024), name: 'test', data: 1));
      var event2 = await client.addEvent(
          StatEvent(timestamp: DateTime(2025), name: 'test', data: 2));
      var event3 = await client.addEvent(
          StatEvent(timestamp: DateTime(2026), name: 'other', data: 3));
      var event4 = await client.addEvent(
          StatEvent(timestamp: DateTime(2027), name: 'test', data: 4));
      var event5 = await client.addEvent(
          StatEvent(timestamp: DateTime(2028), name: 'test', data: 5));
      var event6 = await client.addEvent(
          StatEvent(timestamp: DateTime(2029), name: 'test', data: 6));
      var result = await client.getEventList(StatEventListQuery());
      expect(result.events, [event1, event2, event3, event4, event5, event6]);
      result = await client.getEventList(StatEventListQuery(name: 'test'));
      expect(result.events, [event1, event2, event4, event5, event6]);
      result = await client.getEventList(StatEventListQuery(name: 'other'));
      expect(result.events, [event3]);

      var query = StatEventListQuery(name: 'test', maxCount: 2);
      Future<void> next() async {
        result =
            await client.getEventList(query.withCursor(result.nextCursor!));
      }

      result = await client.getEventList(query);
      expect(result.events, [event1, event2]);
      await next();
      expect(result.events, [event4, event5]);
      await next();
      expect(result.events, [event6]);
      await next();
      expect(result.events, isEmpty);
      await next();
      expect(result.events, isEmpty);
      query = StatEventListQuery(name: 'test', maxCount: 3, descending: true);
      result = await client.getEventList(query);
      expect(result.events, [event6, event5, event4]);
      await next();
      expect(result.events, [event2, event1]);
      await next();
      expect(result.events, isEmpty);
      await next();
      expect(result.events, isEmpty);

      query = StatEventListQuery(name: 'test', minTimestamp: DateTime(2028));
      result = await client.getEventList(query);
      expect(result.events, [event5, event6]);
      query = StatEventListQuery(name: 'test', maxTimestamp: DateTime(2025));
      result = await client.getEventList(query);
      expect(result.events, [event1]);
      query = StatEventListQuery(
          name: 'test',
          minTimestamp: DateTime(2025),
          maxTimestamp: DateTime(2029));
      result = await client.getEventList(query);
      expect(result.events, [event2, event4, event5]);
    });
  });
}
