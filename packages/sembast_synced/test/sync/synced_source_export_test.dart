import 'package:sembast/sembast.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

void main() {
  test('exportInMemory', () async {
    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    await stringMapStoreFactory.store('my_store').record('my_key').put(db, {
      'test': 123,
    });

    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      source: newInMemorySyncedSourceMemory(),
    );
    await synchronizer.sync();

    var exportInfo = await syncedDb.exportInMemory();
    var timestamp = exportInfo.metaInfo.lastTimestamp.v!;
    expect(exportInfo.metaInfo.toMap(), {
      'lastChangeId': 1,
      'lastTimestamp': timestamp,
    });
    expect(exportInfo.data, [
      {'sembast_export': 1, 'version': 1},
      {'store': 'my_store'},
      [
        'my_key',
        {'test': 123},
      ],
      {'store': 'syncMeta'},
      [
        'info',
        {
          'lastTimestamp': {'@Timestamp': timestamp},
          'lastChangeId': 1,
        },
      ],
    ]);
  });
}
