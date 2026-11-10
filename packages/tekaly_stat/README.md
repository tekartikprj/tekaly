# tekaly_stat

Application stat events (a page view, an action...) stored in Firestore:
add events, read one back, list them by name and time range, page by page.
Pure Dart: runs wherever a `tekartik_firebase_firestore` implementation
runs (Flutter, web, io with the rest or sembast implementations, node).

## Getting started

```yaml
dependencies:
  tekaly_stat:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/tekaly_stat
```

```dart
import 'package:tekaly_stat/stat_firebase.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';

Future<void> recordPageView(Firestore firestore, String page) async {
  StatClient client = StatClientFirebase(
    storage: StatStorageFirebase(
      options: StatStorageOptionsFirebase(
        firestore: firestore,
        fsRootDoc: firestore.doc('stats/my_project'),
      ),
    ),
    clientId: 'my_app',
  );
  var event = await client.addEvent(
    StatEvent(name: 'page_view', data: {'page': page}),
  );
  print('${event.id} ${event.timestamp}');
  await client.close();
}
```

The events are the documents of the collection `<fsRootDoc>/<clientId>`
(`timestamp`, `name`, `data`). A runnable example (in memory Firestore,
paging): [example/main.dart](example/main.dart).

## Reading

`getEventList(StatEventListQuery(name:, minTimestamp:, maxTimestamp:,
descending:, maxCount:))`: ordered by timestamp (ascending by default),
`minTimestamp` inclusive, `maxTimestamp` exclusive, `maxCount` 100 by
default. Next page: `query.withCursor(result.nextCursor!)`.

## Pitfalls

- `nextCursor` is never null once a page was read: stop when a page has
  fewer events than `maxCount` (or none), not when the cursor is null.
- A query by `name` needs a composite index in a real Firestore (`name`,
  then `timestamp` and the document id, ascending or descending as
  queried); the memory implementation needs none.
- `data` must be Firestore compatible (a map, a number, a string...);
  `dataAsMap` throws when it is not a map.
