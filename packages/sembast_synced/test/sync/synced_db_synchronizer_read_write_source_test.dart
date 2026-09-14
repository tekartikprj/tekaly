import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced/synced_source.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

/// Read side only wrapper over a source, counting the calls.
class ReadOnlySource
    with SyncedSourceReadDefaultMixin
    implements SyncedSourceRead {
  final SyncedSource inner;
  int getSourceRecordCount = 0;
  int getSourceRecordListCount = 0;
  int getMetaInfoCount = 0;

  ReadOnlySource(this.inner);

  @override
  Future<CvMetaInfo?> getMetaInfo() {
    getMetaInfoCount++;
    return inner.getMetaInfo();
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef) {
    getSourceRecordCount++;
    return inner.getSourceRecord(sourceRef);
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) {
    getSourceRecordListCount++;
    return inner.getSourceRecordList(
      afterChangeId: afterChangeId,
      limit: limit,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) =>
      inner.onMetaInfo(checkDelay: checkDelay);
}

/// Write side only wrapper over a source, counting the calls.
class WriteOnlySource
    with SyncedSourceWriteDefaultMixin
    implements SyncedSourceWrite {
  final SyncedSource inner;
  int putSourceRecordCount = 0;

  WriteOnlySource(this.inner);

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record) {
    putSourceRecordCount++;
    return inner.putSourceRecord(record);
  }
}

final _store = stringMapStoreFactory.store('my_store');
final _record = _store.record('my_key');

void main() {
  late SyncedSourceMemory source;
  late ReadOnlySource readSource;
  late WriteOnlySource writeSource;

  setUp(() {
    source = newInMemorySyncedSourceMemory();
    readSource = ReadOnlySource(source);
    writeSource = WriteOnlySource(source);
  });
  tearDown(() async {
    await source.close();
  });

  /// Put a record directly in the source (a new change).
  Future<void> putRemoteRecord(Map<String, Object?> value) async {
    await source.putSourceRecord(
      CvSyncedSourceRecord()
        ..record.v = (CvSyncedSourceRecordData()
          ..store.v = _store.name
          ..key.v = _record.key
          ..value.v = value),
    );
  }

  Future<List<DbSyncRecord>> getDirtySyncRecords(SyncedDb syncedDb) async =>
      (await syncedDb.getSyncRecords()).where((e) => e.isDirty).toList();

  test('single source', () async {
    var syncedDb = SyncedDb.newInMemory();
    var synchronizer = SyncedDbSynchronizer(db: syncedDb, source: source);
    expect(synchronizer.source, same(source));
    expect(synchronizer.readSource, same(source));
    expect(synchronizer.writeSource, same(source));
    expect(synchronizer.isReadOnly, isFalse);
    await synchronizer.close();
    await syncedDb.close();
  });

  test('missing source', () async {
    var syncedDb = SyncedDb.newInMemory();
    expect(() => SyncedDbSynchronizer(db: syncedDb), throwsArgumentError);
    expect(
      () => SyncedDbSynchronizer(db: syncedDb, writeSource: writeSource),
      throwsArgumentError,
    );
    await syncedDb.close();
  });

  test('read-only source', () async {
    await putRemoteRecord({'test': 1});

    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      readSource: readSource,
    );
    expect(synchronizer.source, isNull);
    expect(synchronizer.readSource, same(readSource));
    expect(synchronizer.writeSource, isNull);
    expect(synchronizer.isReadOnly, isTrue);

    // Sync down works
    var stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat(localCreatedCount: 1));
    expect(await _record.get(db), {'test': 1});
    expect(readSource.getSourceRecordListCount, greaterThan(0));

    // A local change is never pushed and stays dirty
    await _record.put(db, {'test': 2});
    expect(await getDirtySyncRecords(syncedDb), hasLength(1));
    stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat());
    expect(await getDirtySyncRecords(syncedDb), hasLength(1));
    expect((await source.getMetaInfo())!.lastChangeId.v, 1);
    expect(await _record.get(db), {'test': 2});

    // A newer remote change wins over the local dirty change
    await putRemoteRecord({'test': 3});
    stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat(localUpdatedCount: 1));
    expect(await _record.get(db), {'test': 3});
    expect(await getDirtySyncRecords(syncedDb), isEmpty);

    await synchronizer.close();
    await syncedDb.close();
  });

  test('read-only source auto sync', () async {
    await putRemoteRecord({'test': 1});

    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      readSource: readSource,
      autoSync: true,
    );
    await synchronizer.firstSyncDownDone();
    expect(await _record.get(db), {'test': 1});
    await synchronizer.close();
    await syncedDb.close();
  });

  test('hybrid read and write sources', () async {
    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    var synchronizer = SyncedDbSynchronizer(
      db: syncedDb,
      readSource: readSource,
      writeSource: writeSource,
    );
    expect(synchronizer.source, isNull);
    expect(synchronizer.readSource, same(readSource));
    expect(synchronizer.writeSource, same(writeSource));
    expect(synchronizer.isReadOnly, isFalse);

    // Local change pushed through the write source
    await _record.put(db, {'test': 1});
    var stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat(remoteCreatedCount: 1));
    expect(writeSource.putSourceRecordCount, 1);
    expect(readSource.getSourceRecordCount, 1);
    expect(await getDirtySyncRecords(syncedDb), isEmpty);
    expect(
      (await source.getSourceRecord(
        SyncedDataSourceRef(store: 'my_store', key: 'my_key'),
      ))!.record.v!.value.v,
      {'test': 1},
    );

    // Remote change read through the read source
    await putRemoteRecord({'test': 2});
    stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat(localUpdatedCount: 1));
    expect(writeSource.putSourceRecordCount, 1);
    expect(await _record.get(db), {'test': 2});

    await synchronizer.close();
    await syncedDb.close();
  });

  test('export/import through read and write sources', () async {
    await putRemoteRecord({'test': 1});
    var exportInfo = await readSource.exportInMemory();
    expect(exportInfo.data.last, [
      'my_key',
      {'test': 1},
    ]);

    var otherSource = newInMemorySyncedSourceMemory();
    await WriteOnlySource(otherSource).importFromMemory(exportInfo: exportInfo);
    expect((await otherSource.exportInMemory()).data.last, [
      'my_key',
      {'test': 1},
    ]);
    await otherSource.close();
  });
}
