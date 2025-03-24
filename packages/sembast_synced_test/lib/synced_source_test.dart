// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:dev_test/test.dart';

SyncedSourceMemory newInMemorySyncedSourceMemory() {
  return SyncedSourceMemory();
}

void main() {
  group('synced_source_test', () {
    runSyncedSourceTest(() async {
      return newInMemorySyncedSourceMemory();
    });
  });
}

void runSyncedSourceTest(Future<SyncedSource> Function() createSyncedSource) {
  late SyncedSource source;
  setUp(() async {
    source = await createSyncedSource();
  });
  test('putRecord', () async {
    var record = (await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v =
            (CvSyncedSourceRecordData()
              ..store.v = 'test'
              ..key.v = '1'),
    ));
    expect(record.toMap(), {
      'syncId': record.syncId.v,
      'syncTimestamp': record.syncTimestamp.v,
      'syncChangeId': 1,
      'record': {'store': 'test', 'key': '1', 'deleted': false},
    });
    var syncId = record.syncId.v;
    expect(syncId, isNotNull);
    expect(record.syncTimestamp.v, isNotNull);
    expect(record.recordStore, 'test');
    expect(record.syncChangeId.v, 1);
    record = (await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v =
            (CvSyncedSourceRecordData()
              ..store.v = 'test'
              ..key.v = '1')
        ..syncId.v = syncId,
    ));
    expect(record.toMap(), {
      'syncId': record.syncId.v,
      'syncTimestamp': record.syncTimestamp.v,
      'syncChangeId': 2,
      'record': {'store': 'test', 'key': '1', 'deleted': false},
    });
    expect(record.syncId.v, syncId);
    expect(record.syncChangeId.v, 2);
    // Changing!
    record = (await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v =
            (CvSyncedSourceRecordData()
              ..store.v = 'test2'
              ..key.v = '2')
        ..syncId.v = syncId,
    ));
    expect(record.syncChangeId.v, 3);
    expect(record.syncId.v, isNot(syncId));
    expect(record.syncTimestamp.v, isNotNull);
    expect(record.recordStore, 'test2');
    expect(record.recordKey, '2');
    expect(record.toMap(), {
      'syncId': record.syncId.v,
      'syncTimestamp': record.syncTimestamp.v,
      'syncChangeId': 3,
      'record': {'store': 'test2', 'key': '2', 'deleted': false},
    });
  });
  test('getRecord', () async {
    var syncId = '1234';
    var ref = SyncedDataSourceRef(store: 'test', key: '1', syncId: syncId);

    var record = await source.getSourceRecord(ref);
    expect(record, isNull);
    record = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v =
            (CvSyncedSourceRecordData()
              ..store.v = 'test'
              ..key.v = '1')
        ..syncId.v = syncId,
    );
    var newSyncId = record.syncId.v!;
    record = (await source.getSourceRecord(ref))!;
    expect(record.syncId.v, newSyncId);
    expect(newSyncId, isNot(syncId));
    // Without syncId
    record =
        (await source.getSourceRecord(
          SyncedDataSourceRef(store: 'test', key: '1'),
        ))!;
    expect(record.syncId.v, newSyncId);
    // Wrong syncId
    record =
        (await source.getSourceRecord(
          SyncedDataSourceRef(store: 'test', key: '1'),
        ))!;
    expect(record.syncId.v, newSyncId);
    // Wrong key (fail)
    record = await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '2', syncId: newSyncId),
    );
    expect(record, isNull);
  });
  test('getSourceRecordList', () async {
    var list = await source.getSourceRecordList();
    expect(list.lastChangeId, isNull);
    expect(list.list, isEmpty);
    var record = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v =
            (CvSyncedSourceRecordData()
              ..store.v = 'test'
              ..key.v = '1'),
    );
    list = await source.getSourceRecordList(includeDeleted: true);
    expect(list.list, hasLength(1));
    expect(list.list.first.syncId.v, record.syncId.v);
    var record2 = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v =
            (CvSyncedSourceRecordData()
              ..store.v = 'test'
              ..key.v = '2'),
    );
    list = await source.getSourceRecordList(includeDeleted: true);
    //print(list);
    expect(list.list.map((e) => e.syncId.v), [
      record.syncId.v,
      record2.syncId.v,
    ]);
  });
  test('metaInfo', () async {
    var info = await source.getMetaInfo();
    expect(info, isNull);
    info = await source.putMetaInfo(
      CvMetaInfoRecord()..minIncrementalChangeId.v = 2,
    );
    expect(info!.minIncrementalChangeId.v!, 2);
    info =
        (await source.putMetaInfo(
          CvMetaInfoRecord()..minIncrementalChangeId.v = 3,
        ))!;
    expect(info.minIncrementalChangeId.v, 3);
    try {
      await source.putMetaInfo(
        CvMetaInfoRecord()..minIncrementalChangeId.v = 1,
      );
      fail('should fail');
    } on StateError catch (e) {
      print(e);
    }
  });
  test('onMetaInfo', () async {
    await source.putMetaInfo(CvMetaInfoRecord()..minIncrementalChangeId.v = 1);
    expect((await source.onMetaInfo().first)!.minIncrementalChangeId.v!, 1);
  });
}
