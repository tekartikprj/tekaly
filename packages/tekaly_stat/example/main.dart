// ignore_for_file: avoid_print

// Records stat events in an in memory firestore, then reads them back page
// by page. Runs as is: `dart run example/main.dart`.
import 'package:tekaly_stat/stat_firebase.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:tekartik_firebase_local/firebase_local.dart';

Future<void> main() async {
  // A real app passes its firestore (flutter, rest, node...).
  var firestore = newFirestoreServiceMemory().firestore(newFirebaseAppLocal());
  StatClient client = StatClientFirebase(
    storage: StatStorageFirebase(
      options: StatStorageOptionsFirebase(
        firestore: firestore,
        fsRootDoc: firestore.doc('stats/my_project'),
      ),
    ),
    clientId: 'my_app',
  );

  for (var page in ['home', 'search', 'home', 'about', 'home']) {
    await client.addEvent(StatEvent(name: 'page_view', data: {'page': page}));
  }

  // Newest first, 2 per page. A page shorter than maxCount is the last one.
  const maxCount = 2;
  var query = StatEventListQuery(
    name: 'page_view',
    descending: true,
    maxCount: maxCount,
  );
  while (true) {
    var result = await client.getEventList(query);
    for (var event in result.events) {
      print('${event.timestamp} ${event.dataAsMap['page']}');
    }
    if (result.events.length < maxCount) {
      break;
    }
    query = query.withCursor(result.nextCursor!);
  }
  await client.close();
}
