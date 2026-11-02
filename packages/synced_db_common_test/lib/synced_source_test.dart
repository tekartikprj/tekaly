// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:dev_test/test.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';

SyncedSourceMemory newInMemorySyncedSourceMemory() {
  return SyncedSourceMemory();
}

Future<SyncedSourceMemory> setupNewInMemorySyncedSourceMemory() async {
  return newInMemorySyncedSourceMemory();
}

void main() {
  group('synced_source_default_memory', () {
    runSyncedSourceTest(
      setupNewInMemorySyncedSourceMemory,
      skipRealTimeChanges: true,
    );
    strictSyncedSourceTest(setupNewInMemorySyncedSourceMemory);
  });
}

void strictSyncedSourceTest(
  Future<SyncedSource> Function() createSyncedSource, {
  bool? skipRealTimeChanges,
}) {
  late SyncedSource source;
  setUp(() async {
    source = await createSyncedSource();
  });
  tearDown(() async {
    await source.close();
  });
  test('putRecord format', () async {
    var resultRecord = (await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..value.v = {'int': 1, 'timestamp': SyncedDbTimestamp(2, 3000)}
          ..key.v = '1'),
    ));
    var readRecord = await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '1'),
    );
    expect(readRecord, resultRecord);
    var syncTimestamp = readRecord!.syncTimestamp.v;
    expect(syncTimestamp, isNotNull);
    var map = (readRecord.toMap());
    expect(map, {
      'syncId': 'test|1',
      'syncTimestamp': syncTimestamp,
      'syncChangeId': 1,
      'record': {
        'store': 'test',
        'key': '1',
        'value': {'int': 1, 'timestamp': SyncedDbTimestamp(2, 3000)},
        'deleted': false,
      },
    });
    // Read using the fixed sync id (what a read min service does)
    var readRecordData = await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '1').fixedSourceSyncId(),
    );
    expect(readRecordData?.record.v?.value.v, {
      'int': 1,
      'timestamp': SyncedDbTimestamp(2, 3000),
    });
  });
}

void runSyncedSourceTest(
  Future<SyncedSource> Function() createSyncedSource, {
  bool? skipRealTimeChanges,
}) {
  skipRealTimeChanges ??= false;
  late SyncedSource source;
  setUp(() async {
    source = await createSyncedSource();
  });

  test('putRecord', () async {
    var record = (await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..key.v = '1'),
    ));
    print('syncId: ${record.syncId.v}');
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
        ..record.v = (CvSyncedSourceRecordData()
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
        ..record.v = (CvSyncedSourceRecordData()
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
  test('an update drops the fields no longer in the value', () async {
    var record = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..key.v = '1'
          ..value.v = {
            'name': 'Inès',
            'email': 'ines@example.test',
            'nested': {'a': 1, 'b': 2},
          }),
    );
    var syncId = record.syncId.v;
    await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..key.v = '1'
          ..value.v = {
            'name': 'Inès',
            'nested': {'a': 1},
          })
        ..syncId.v = syncId,
    );
    var read = await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '1', syncId: syncId),
    );
    expect(read!.record.v!.value.v, {
      'name': 'Inès',
      'nested': {'a': 1},
    });
  });

  test('put/getRecord data', () async {
    var record = (await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..value.v = {
            'string': 'Some test',
            'bool': true,
            'double': 1.5,
            'int': 1,
            'timestamp': SyncedDbTimestamp(2, 3000),
            'blob': SyncedDbBlob.fromList([1, 2, 3]),
          }
          ..key.v = '1'),
    ));
    var syncChangeId = record.syncChangeId.v;
    print(
      'syncId: ${record.syncId.v}, syncChangeId: $syncChangeId, record: ${record.toMap()}',
    );
    expect(record.toMap(), {
      'syncId': record.syncId.v,
      'syncTimestamp': record.syncTimestamp.v,
      'syncChangeId': syncChangeId,

      'record': {
        'store': 'test',
        'key': '1',
        'value': {
          'string': 'Some test',
          'bool': true,
          'double': 1.5,
          'int': 1,
          'timestamp': SyncedDbTimestamp(2, 3000),
          'blob': SyncedDbBlob.fromList([1, 2, 3]),
        },
        'deleted': false,
      },
    });
    var syncId = record.syncId.v;
    expect(syncId, isNotNull);
    expect(record.syncTimestamp.v, isNotNull);
    expect(record.recordStore, 'test');
    //expect(record.syncChangeId.v, 1);
    var ref = SyncedDataSourceRef(store: 'test', key: '1', syncId: syncId);
    record = (await source.getSourceRecord(ref))!;
    expect(record.toMap(), {
      'syncId': record.syncId.v,
      'syncTimestamp': record.syncTimestamp.v,
      'syncChangeId': syncChangeId,

      'record': {
        'store': 'test',
        'key': '1',
        'value': {
          'string': 'Some test',
          'bool': true,
          'double': 1.5,
          'int': 1,
          'timestamp': SyncedDbTimestamp(2, 3000),
          'blob': SyncedDbBlob.fromList([1, 2, 3]),
        },
        'deleted': false,
      },
    });
  });
  test('getRecord', () async {
    var syncId = '1234';
    var ref = SyncedDataSourceRef(store: 'test', key: '1', syncId: syncId);

    //var record = await source.getSourceRecord(ref);
    // expect(record, isNull);
    SyncedSourceRecord? record = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..key.v = '1')
        ..syncId.v = syncId,
    );
    var newSyncId = record.syncId.v!;
    record = (await source.getSourceRecord(ref))!;
    expect(record.syncId.v, newSyncId);
    expect(newSyncId, isNot(syncId));

    // Without syncId
    record = (await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '1'),
    ))!;
    expect(record.syncId.v, newSyncId);
    // Wrong syncId, found by store and key
    record = (await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '1', syncId: 'wrong_$newSyncId'),
    ))!;
    expect(record.syncId.v, newSyncId);
    // Wrong key (fail)
    record = await source.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: '2', syncId: newSyncId),
    );
    expect(record, isNull);
  });
  test('getSourceRecordList', () async {
    //var list = await source.getSourceRecordList();
    //expect(list.lastChangeId, isNull);
    //expect(list.list, isEmpty);
    var meta = await source.getMetaInfo();
    var lastChangeId = meta?.lastChangeId.v ?? 0;
    var record = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..key.v = '1'),
    );

    var list = await source.getSourceRecordList(
      includeDeleted: true,
      afterChangeId: lastChangeId,
    );
    expect(list.list, hasLength(1));
    expect(list.list.first.syncId.v, record.syncId.v);
    var record2 = await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = 'test'
          ..key.v = '2'),
    );
    list = await source.getSourceRecordList(
      includeDeleted: true,
      afterChangeId: lastChangeId,
    );
    //print(list);
    expect(list.list.map((e) => e.syncId.v), [
      record.syncId.v,
      record2.syncId.v,
    ]);
  });
  test('metaInfo', () async {
    var info = await source.getMetaInfo();
    var lastChangedId = info?.lastChangeId.v ?? 0;
    info = await source.putMetaInfo(
      CvMetaInfo()..lastChangeId.v = ++lastChangedId,
    );
    expect(info!.lastChangeId.v!, lastChangedId);
    info = (await source.putMetaInfo(
      CvMetaInfo()..lastChangeId.v = ++lastChangedId,
    ))!;
    expect(info.lastChangeId.v, lastChangedId);

    // minIncrementalChangeId cannot go back
    info = (await source.putMetaInfo(
      CvMetaInfo()..minIncrementalChangeId.v = lastChangedId,
    ))!;
    expect(info.minIncrementalChangeId.v, lastChangedId);
    await expectLater(
      source.putMetaInfo(
        CvMetaInfo()..minIncrementalChangeId.v = lastChangedId - 1,
      ),
      throwsA(anything),
    );
    expect(
      (await source.getMetaInfo())!.minIncrementalChangeId.v,
      lastChangedId,
    );
  });
  test('onMetaInfo simple', () async {
    var info = await source.getMetaInfo();
    var lastChangeId = info?.lastChangeId.v ?? 0;
    await source.putMetaInfo(CvMetaInfo()..lastChangeId.v = ++lastChangeId);
    expect((await source.onMetaInfo().first)!.lastChangeId.v!, lastChangeId);
  });
  test('onMetaInfo real time', () async {
    var info = await source.getMetaInfo();
    var lastChangeId = info?.lastChangeId.v ?? 0;
    await source.putMetaInfo(CvMetaInfo()..lastChangeId.v = ++lastChangeId);
    late Completer<void> completer;
    Future<void> newCompleter() {
      completer = Completer<void>();
      return completer.future;
    }

    var future = newCompleter();
    var list = <CvMetaInfo?>[];

    var subscription = source.onMetaInfo().listen((metaInfo) {
      // print('onMetaInfo $metaInfo');
      list.add(metaInfo);
      completer.complete();
    });

    await future;
    expect(list, hasLength(1));
    future = newCompleter();
    await source.putMetaInfo(CvMetaInfo()..lastChangeId.v = ++lastChangeId);
    await future;
    expect(list, hasLength(2));
    await subscription.cancel();
  }, skip: skipRealTimeChanges);
}

/// Partitioned sources of one location: [createPartitionedSource] creates a
/// new location and returns its source for a given partition.
void runSyncedSourcePartitionTest(
  Future<SyncedSource Function(SyncedSourcePartition? partition)> Function()
  createPartitionedSource,
) {
  const field = 'userId';
  late SyncedSource Function(SyncedSourcePartition? partition) sourceOf;
  late SyncedSource writer;
  setUp(() async {
    sourceOf = await createPartitionedSource();
    writer = sourceOf(const SyncedSourcePartition(field: field));
  });
  SyncedSource readerOf(String userId) =>
      sourceOf(SyncedSourcePartition(field: field, value: userId));

  Future<CvSyncedSourceRecord> put(
    SyncedSource source,
    String key, {
    Map<String, Object?>? value,
    String store = 'test',
    bool deleted = false,
  }) => source.putSourceRecord(
    CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = store
        ..key.v = key
        ..value.v = value
        ..deleted.v = deleted),
  );

  List<String> keysOf(SyncedSourceRecordList list) =>
      list.list.map((record) => record.recordKey).toList();

  test('read a partition', () async {
    await put(writer, 'a', value: {field: 'u1', 'meal': 'm1'});
    await put(writer, 'b', value: {field: 'u2'});
    await put(writer, 'c', value: {'meal': 'm1'});
    var d = await put(writer, 'd', store: 'other', value: {field: 'u1'});

    var list = await readerOf('u1').getSourceRecordList();
    expect(keysOf(list), ['a', 'd']);
    expect(list.lastChangeId, d.syncChangeId.v);
    expect(list.list.first.record.v!.value.v, {field: 'u1', 'meal': 'm1'});
    list = await readerOf('u1').getSourceRecordList(afterChangeId: 1);
    expect(keysOf(list), ['d']);
    list = await readerOf(
      'u1',
    ).getSourceRecordList(afterChangeId: d.syncChangeId.v);
    expect(list.list, isEmpty);
    expect(list.lastChangeId, isNull);
    expect(keysOf(await readerOf('u2').getSourceRecordList()), ['b']);
    expect(await readerOf('u3').getSourceRecordList().then(keysOf), isEmpty);

    // No value: every record.
    expect(keysOf(await writer.getSourceRecordList()), ['a', 'b', 'c', 'd']);
    expect(keysOf(await sourceOf(null).getSourceRecordList()), [
      'a',
      'b',
      'c',
      'd',
    ]);
  });

  test('a deleted record keeps its partition field', () async {
    await put(writer, 'a', value: {field: 'u1', 'meal': 'm1'});
    await put(writer, 'b', value: {field: 'u2'});
    var deleted = await put(writer, 'a', deleted: true);
    expect(deleted.isDeleted, isTrue);
    expect(deleted.record.v!.deleted.v, isTrue);
    expect(deleted.record.v!.value.v, {field: 'u1'});
    var read = await writer.getSourceRecord(
      SyncedDataSourceRef(store: 'test', key: 'a'),
    );
    expect(read!.isDeleted, isTrue);
    expect(read.record.v!.value.v, {field: 'u1'});

    var reader = readerOf('u1');
    var list = await reader.getSourceRecordList(includeDeleted: true);
    expect(keysOf(list), ['a']);
    expect(list.list.first.isDeleted, isTrue);
    expect(list.lastChangeId, deleted.syncChangeId.v);
    // Skipped but still moving the cursor.
    list = await reader.getSourceRecordList();
    expect(list.list, isEmpty);
    expect(list.lastChangeId, deleted.syncChangeId.v);
    expect(
      keysOf(await readerOf('u2').getSourceRecordList(includeDeleted: true)),
      ['b'],
    );

    // Deleted again (by a partition reader): still in the partition.
    deleted = await put(reader, 'a', deleted: true);
    expect(deleted.record.v!.value.v, {field: 'u1'});
    expect(keysOf(await reader.getSourceRecordList(includeDeleted: true)), [
      'a',
    ]);
  });

  test('a deleted record without partition', () async {
    // A record with no partition field, deleted: nothing to keep.
    await put(writer, 'c', value: {'meal': 'm1'});
    var deleted = await put(writer, 'c', deleted: true);
    expect(deleted.isDeleted, isTrue);
    expect(deleted.record.v!.value.v, isNull);

    // A source without partition does not keep the field.
    await put(writer, 'a', value: {field: 'u1'});
    deleted = await put(sourceOf(null), 'a', deleted: true);
    expect(deleted.record.v!.value.v, isNull);
    expect(
      keysOf(await readerOf('u1').getSourceRecordList(includeDeleted: true)),
      isEmpty,
    );
  });

  test('a record moved to another partition', () async {
    await put(writer, 'a', value: {field: 'u1'});
    var moved = await put(writer, 'a', value: {field: 'u2'});
    expect(
      keysOf(await readerOf('u1').getSourceRecordList(includeDeleted: true)),
      isEmpty,
    );
    var list = await readerOf('u2').getSourceRecordList();
    expect(keysOf(list), ['a']);
    expect(list.lastChangeId, moved.syncChangeId.v);
  });
}
