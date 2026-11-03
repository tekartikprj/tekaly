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
  group('synced_source_firestore_partition', () {
    runSyncedSourcePartitionTest(() async {
      var source = newInMemorySyncedSourceFirestore();
      return source.withPartition;
    });
  });
  group('synced_source_firestore_test', () {
    late SyncedSourceFirestore source;
    late fb.Firestore firestore;
    setUp(() {
      source = newInMemorySyncedSourceFirestore();
      firestore = source.firestore;
    });
    test('deleted record format with partition', () async {
      source = source.withPartition(
        const SyncedSourcePartition(field: 'userId'),
      );
      await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'test'
            ..value.v = {'userId': 'u1', 'int': 1}
            ..key.v = '1'),
      );
      await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = 'test'
            ..deleted.v = true
            ..key.v = '1'),
      );
      var map = (await firestore.doc('data/test|1').get()).data;
      expect(map, {
        'record': {
          'store': 'test',
          'key': '1',
          'value': {'userId': 'u1'},
          'deleted': true,
        },
        'syncTimestamp': map[syncTimestampKey],
        'syncChangeId': 2,
      });
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

    CvSyncedSourceRecord newRecord(
      String key, {
      Map<String, Object?>? value,
      bool deleted = false,
    }) => CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = 'test'
        ..key.v = key
        ..value.setValue(value)
        ..deleted.setValue(deleted ? true : null));

    test('putSourceRecords: one batch, consecutive change ids', () async {
      await source.putSourceRecord(newRecord('0', value: {'int': 0}));
      var records = await source.putSourceRecords([
        newRecord('1', value: {'int': 1}),
        newRecord('0', value: {'int': 2}),
        newRecord('2', value: {'int': 3}),
      ]);
      expect(records.map((record) => record.syncId.v), [
        'test|1',
        'test|0',
        'test|2',
      ]);
      expect(records.map((record) => record.syncChangeId.v), [2, 3, 4]);
      expect(records.map((record) => record.record.v!.value.v), [
        {'int': 1},
        {'int': 2},
        {'int': 3},
      ]);
      expect(records.first.syncTimestamp.v, isNotNull);
      expect((await firestore.doc('meta/info').get()).data, {
        'lastChangeId': 4,
      });
      expect(await source.putSourceRecords([]), isEmpty);
      expect(
        () => source.putSourceRecords([
          for (var i = 0; i <= source.putSourceRecordsLimit; i++)
            newRecord('$i'),
        ]),
        throwsArgumentError,
      );
    });

    test('putSourceRecords: a delete keeps the partition field', () async {
      source = source.withPartition(
        const SyncedSourcePartition(field: 'userId'),
      );
      await source.putSourceRecords([
        newRecord('1', value: {'userId': 'u1', 'int': 1}),
      ]);
      await source.putSourceRecords([newRecord('1', deleted: true)]);
      var map = (await firestore.doc('data/test|1').get()).data;
      expect(map['record'], {
        'store': 'test',
        'key': '1',
        'value': {'userId': 'u1'},
        'deleted': true,
      });
    });

    test('getSourceRecords', () async {
      await source.putSourceRecord(newRecord('1', value: {'int': 1}));
      // A record under another sync id than store|key: found by its key.
      await source.putRawRecord(
        newRecord('2', value: {'int': 2})
          ..syncId.v = 'other_id'
          ..syncChangeId.v = 2,
      );
      var records = await source.getSourceRecords([
        SyncedDataSourceRef(store: 'test', key: '1'),
        SyncedDataSourceRef(store: 'test', key: '2'),
        SyncedDataSourceRef(store: 'test', key: '3'),
      ]);
      expect(records.map((record) => record?.syncId.v), [
        'test|1',
        'other_id',
        null,
      ]);
      expect(await source.getSourceRecords([]), isEmpty);
    });
  });
}
