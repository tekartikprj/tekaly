// ignore_for_file: avoid_print

import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_test/synced_source_test.dart';

import 'package:dev_test/test.dart';

SyncedSourceMemoryCompat newInMemorySyncedSourceMemoryCompat() {
  return SyncedSourceMemoryCompat();
}

Future<SyncedSourceMemoryCompat>
setupNewInMemorySyncedSourceMemoryCompat() async {
  return newInMemorySyncedSourceMemoryCompat();
}

void main() {
  group('common', () {
    runSyncedSourceTest(
      setupNewInMemorySyncedSourceMemoryCompat,
      skipRealTimeChanges: true,
    );
    //runStrictSyncedSourceTest(setupNewInMemorySyncedSourceMemoryCompat);
  });

  group('synced_source_sembast_test', () {
    late SyncedSourceMemoryCompat source;

    setUp(() async {
      source = await setupNewInMemorySyncedSourceMemoryCompat();
    });
    test('putRecord format', () async {
      var sourceRecord = (await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'test'
            ..value.v = {'int': 1, 'timestamp': Timestamp(2, 3000)}
            ..key.v = '1'),
      ));

      var syncId = sourceRecord.syncId.v!;
      expect(syncId, '1');

      var readRecord = await source.getSourceRecord(
        SyncedDataSourceRef(store: 'test', key: '1'),
      );
      syncId = readRecord!.syncId.v!;
      expect(syncId, '1');
      print('readRecord: $readRecord');
      expect(readRecord, sourceRecord);
      var syncTimestamp = readRecord.syncTimestamp.v;
      expect(syncTimestamp, isA<SyncedDbTimestamp>());
      var map = readRecord.toMap();
      expect(map, {
        'syncId': '1',
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
