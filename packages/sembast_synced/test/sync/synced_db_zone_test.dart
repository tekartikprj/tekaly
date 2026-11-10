import 'dart:async';

import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:test/test.dart';

/// Runs [body] in a zone that keeps its microtasks and runs them itself, as
/// `FakeAsync.run` + `flushMicrotasks` of package:fake_async do: a callback
/// scheduled in another zone (by a future completed there) does not run.
void runInMicrotaskZone(void Function() body) {
  var microtasks = <void Function()>[];
  Zone.current
      .fork(
        specification: ZoneSpecification(
          scheduleMicrotask: (self, parent, zone, microtask) =>
              microtasks.add(microtask),
        ),
      )
      .run(() {
        body();
        while (microtasks.isNotEmpty) {
          microtasks.removeAt(0)();
        }
      });
}

void main() {
  test('database in another zone once open', () async {
    var syncedDb = SyncedDb.newInMemory(syncedStoreNames: ['my_store']);
    // Opened in the real zone (a widget test's tester.runAsync)...
    var opened = await syncedDb.database;
    Database? database;
    // ...then awaited in the fake async zone of a widget test.
    runInMicrotaskZone(() {
      syncedDb.database.then((value) => database = value);
    });
    expect(database, same(opened));
    await syncedDb.close();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
