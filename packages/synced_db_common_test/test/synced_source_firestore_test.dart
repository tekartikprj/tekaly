// ignore_for_file: avoid_print

import 'package:dev_test/test.dart';
import 'package:tekaly_synced_db_common/synced_db_common_firestore.dart';
import 'package:tekaly_synced_db_common_test/synced_source_firestore_test_common.dart';
import 'package:tekaly_synced_db_common_test/synced_source_test.dart';
import 'package:tekartik_firebase_firestore/firestore_logger.dart' as fb;
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart'
    as fb;

void main() {
  group('synced_source_firestore_common_test', () {
    runSyncedSourceTest(() async {
      return newInMemorySyncedSourceFirestore();
    });
  });
  group('synced_source_firestore_test', () {
    late SyncedSourceFirestore source;
    late fb.Firestore firestore;
    setUp(() {
      source = newInMemorySyncedSourceFirestore();
      firestore = source.firestore;
    });
    test('putRecord format', () async {
      var sourceRecord = (await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'test'
            ..value.v = {'int': 1, 'timestamp': SyncedDbTimestamp(2, 3000)}
            ..key.v = '1'),
      ));
      expect((await firestore.doc('meta/info').get()).data, {
        'lastChangeId': 1,
      });

      expect(sourceRecord.syncId.v, 'test|1');
      var map =
          (await firestore.doc('data/${sourceRecord.syncId.v}').get()).data;
      var syncTimestamp = map[syncTimestampKey];
      expect(syncTimestamp, isA<fb.Timestamp>());
      expect(map, {
        'record': {
          'store': 'test',
          'key': '1',
          'value': {'int': 1, 'timestamp': fb.Timestamp(2, 3000)},
          'deleted': false,
        },
        'syncTimestamp': syncTimestamp,
        'syncChangeId': 1,
      });
    });
  });
}
