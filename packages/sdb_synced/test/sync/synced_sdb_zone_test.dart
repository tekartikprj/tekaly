import 'dart:async';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:test/test.dart';

final _store = SdbStoreRef<String, SdbModel>('my_store');

SyncedSdb _newSyncedSdb() => SyncedSdb.newInMemory(
  options: SyncedSdbOptions(
    openDatabaseOptions: SdbOpenDatabaseOptions(
      version: 1,
      schema: SdbDatabaseSchema(
        stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
      ),
    ),
  ),
);

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
    var syncedSdb = _newSyncedSdb();
    // Opened in the real zone (a widget test's tester.runAsync)...
    var opened = await syncedSdb.database;
    SdbDatabase? database;
    // ...then awaited in the fake async zone of a widget test.
    runInMicrotaskZone(() {
      syncedSdb.database.then((value) => database = value);
    });
    expect(database, same(opened));
    await syncedSdb.close();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
