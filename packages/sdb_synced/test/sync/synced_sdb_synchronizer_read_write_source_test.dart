import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

/// Read side only wrapper over a source, counting the calls.
class ReadOnlySource
    with SyncedSourceReadDefaultMixin
    implements SyncedSourceRead {
  final SyncedSource inner;
  int getSourceRecordCount = 0;
  int getSourceRecordListCount = 0;

  ReadOnlySource(this.inner);

  @override
  Future<CvMetaInfo?> getMetaInfo() => inner.getMetaInfo();

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

final _store = SdbStoreRef<String, SdbModel>('my_store');
final _record = _store.record('my_key');

final _schema = SdbDatabaseSchema(
  stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);

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

  Future<List<SdbSyncRecord>> getDirtySyncRecords(SyncedSdb syncedSdb) async =>
      (await syncedSdb.getSyncRecords()).where((e) => e.isDirty).toList();

  test('single source', () async {
    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
    expect(synchronizer.source, same(source));
    expect(synchronizer.readSource, same(source));
    expect(synchronizer.writeSource, same(source));
    expect(synchronizer.isReadOnly, isFalse);
    await synchronizer.close();
    await syncedSdb.close();
  });

  test('missing source', () async {
    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    expect(() => SyncedSdbSynchronizer(db: syncedSdb), throwsArgumentError);
    expect(
      () => SyncedSdbSynchronizer(db: syncedSdb, writeSource: writeSource),
      throwsArgumentError,
    );
    await syncedSdb.close();
  });

  test('read-only source', () async {
    await putRemoteRecord({'test': 1});

    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
      readSource: readSource,
    );
    expect(synchronizer.source, isNull);
    expect(synchronizer.readSource, same(readSource));
    expect(synchronizer.writeSource, isNull);
    expect(synchronizer.isReadOnly, isTrue);

    // Sync down works
    var stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat(localCreatedCount: 1));
    expect(await _record.getValue(db), {'test': 1});
    expect(readSource.getSourceRecordListCount, greaterThan(0));

    // A local change is never pushed and stays dirty
    await _record.put(db, {'test': 2});
    expect(await getDirtySyncRecords(syncedSdb), hasLength(1));
    stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat());
    expect(await getDirtySyncRecords(syncedSdb), hasLength(1));
    expect((await source.getMetaInfo())!.lastChangeId.v, 1);
    expect(await _record.getValue(db), {'test': 2});

    // A newer remote change wins over the local dirty change
    await putRemoteRecord({'test': 3});
    stat = await synchronizer.sync();
    expect(stat, SyncedSyncStat(localUpdatedCount: 1));
    expect(await _record.getValue(db), {'test': 3});
    expect(await getDirtySyncRecords(syncedSdb), isEmpty);

    await synchronizer.close();
    await syncedSdb.close();
  });

  test('read-only source auto sync', () async {
    await putRemoteRecord({'test': 1});

    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
      readSource: readSource,
      autoSync: true,
    );
    // Wait for the auto sync to bring the record down
    await syncedSdb.onSyncMetaInfo().firstWhere(
      (meta) => meta?.lastChangeId.v == 1,
    );
    expect(await _record.getValue(db), {'test': 1});
    await synchronizer.close();
    await syncedSdb.close();
  });

  test('hybrid read and write sources', () async {
    var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
    var db = await syncedSdb.database;
    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
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
    expect(await getDirtySyncRecords(syncedSdb), isEmpty);
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
    expect(await _record.getValue(db), {'test': 2});

    await synchronizer.close();
    await syncedSdb.close();
  });
}
