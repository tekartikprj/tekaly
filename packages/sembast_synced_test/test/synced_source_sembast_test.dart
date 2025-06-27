// ignore_for_file: avoid_print

import 'package:sembast/sembast_memory.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/src/sync/model/db_sync_record.dart'
    show syncTimestampKey;
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced/synced_db_sembast.dart';
import 'package:tekaly_sembast_synced_test/synced_source_test.dart';

import 'package:dev_test/test.dart';

void main() {
  group('synced_source_sembast_common_test', () {
    runSyncedSourceTest(() async {
      return newInMemorySyncedSourceSembast();
    });
  });
  var metaStore = stringMapStoreFactory.store('meta');
  var dataStore = stringMapStoreFactory.store('data');
  group('synced_source_sembast_test', () {
    late SyncedSourceSembast source;
    late Database database;
    setUp(() async {
      source = await newInMemorySyncedSourceSembast();
      database = source.database;
    });
    test('putRecord format', () async {
      var sourceRecord = (await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'test'
            ..value.v = {'int': 1, 'timestamp': Timestamp(2, 3000)}
            ..key.v = '1'),
      ));
      expect((await metaStore.record('info').get(database)), {
        'lastChangeId': 1,
      });

      expect(sourceRecord.syncId.v, 'test|1');
      var map = (await dataStore
          .record('${sourceRecord.syncId.v}')
          .get(database))!;
      var syncTimestamp = map[syncTimestampKey];
      expect(syncTimestamp, isA<SyncedDbTimestamp>());
      expect(map, {
        'record': {
          'store': 'test',
          'key': '1',
          'value': {'int': 1, 'timestamp': SyncedDbTimestamp(2, 3000)},
          'deleted': false,
        },
        'syncTimestamp': syncTimestamp,
        'syncChangeId': 1,
      });
    });
  });
}
