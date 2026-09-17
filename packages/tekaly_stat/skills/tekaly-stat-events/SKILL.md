---
name: tekaly-stat-events
description: >-
  Use when recording or querying application stat events (StatClient,
  StatEvent, StatEventListQuery) stored in firestore with tekaly_stat.
---

# Stat events (tekaly_stat)

## Guidelines

* Import `package:tekaly_stat/stat_firebase.dart` (exports `stat_client.dart`
  and `stat_storage.dart`).
* Build one `StatClientFirebase(storage: StatStorageFirebase(options:
  StatStorageOptionsFirebase(firestore:, storage:, fsRootDoc:)), clientId:)`
  per app; `fsRootDoc` is the firestore document under which the events are
  stored, `clientId` identifies the app instance. Depend on the abstract
  `StatClient` elsewhere and `close()` it when done.
* Record with `addEvent(StatEvent(name:, data:, timestamp:))` (timestamp
  defaults to now) or `addEvents([...])`; the returned event carries the
  generated `id`. `data` must be json encodable (a map, a number, a string);
  read a map back with `dataAsMap`.
* Query with `getEventList(StatEventListQuery(name:, minTimestamp:,
  maxTimestamp:, descending:, maxCount:))`: `minTimestamp` is inclusive,
  `maxTimestamp` exclusive, results are ordered by timestamp (ascending by
  default), `maxCount` defaults to 1000. Page with
  `query.withCursor(result.nextCursor!)` while `nextCursor` is not null.
* `getEvent(id)` reads one event; events compare by id.
* In tests, use an in memory firestore (`newFirestoreServiceMemory()` from
  `tekartik_firebase_firestore_sembast`) and a local firebase app
  (`newFirebaseAppLocal()`).

## Examples

```dart
import 'package:tekaly_stat/stat_firebase.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';

Future<void> main(Firestore firestore) async {
  StatClient client = StatClientFirebase(
    storage: StatStorageFirebase(
      options: StatStorageOptionsFirebase(
        firestore: firestore,
        fsRootDoc: firestore.doc('project/my_project'),
      ),
    ),
    clientId: 'my_app',
  );

  var event = await client.addEvent(
    StatEvent(name: 'page_view', data: {'page': 'home'}),
  );
  print(event.id);

  // Events of the last day, newest first, page by page
  var query = StatEventListQuery(
    name: 'page_view',
    minTimestamp: DateTime.now().subtract(const Duration(days: 1)),
    descending: true,
    maxCount: 100,
  );
  while (true) {
    var result = await client.getEventList(query);
    for (var event in result.events) {
      print('${event.timestamp} ${event.dataAsMap['page']}');
    }
    var nextCursor = result.nextCursor;
    if (nextCursor == null) {
      break;
    }
    query = query.withCursor(nextCursor);
  }
  await client.close();
}
```
