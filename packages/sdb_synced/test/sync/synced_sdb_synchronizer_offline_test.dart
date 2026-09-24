import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

/// A source whose record list comes back empty while [offline], like a web
/// or mobile firestore answering from its cache, the meta info being the
/// one its listener cached.
class CachedEmptySource
    with SyncedSourceReadDefaultMixin
    implements SyncedSourceRead {
  final SyncedSource inner;
  var offline = true;

  CachedEmptySource(this.inner);

  @override
  Future<CvMetaInfo?> getMetaInfo() => inner.getMetaInfo();

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(
    SyncedDataSourceRef sourceRef,
  ) => inner.getSourceRecord(sourceRef);

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) async {
    if (offline) {
      return SyncedSourceRecordList([], null);
    }
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

final _store = SdbStoreRef<String, SdbModel>('my_store');

final _schema = SdbDatabaseSchema(
  stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
);

void main() {
  test('an empty (cached) record list does not skip records', () async {
    var source = SyncedSourceMemory();
    for (var i = 1; i <= 3; i++) {
      await source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = _store.name
            ..key.v = 'key$i'
            ..value.v = {'value': i}),
      );
    }
    expect((await source.getMetaInfo())!.lastChangeId.v, 3);

    var readSource = CachedEmptySource(source);
    var syncedSdb = SyncedSdb.newInMemory(
      options: SyncedSdbOptions(
        openDatabaseOptions: SdbOpenDatabaseOptions(
          version: 1,
          schema: _schema,
        ),
      ),
    );
    var db = await syncedSdb.database;
    var synchronizer = SyncedSdbSynchronizer(
      db: syncedSdb,
      readSource: readSource,
    );

    // Offline: nothing comes, and the cursor does not jump to the meta.
    await synchronizer.sync();
    expect(await _store.count(db), 0);
    expect(
      (await syncedSdb.getSyncMetaInfo())?.lastChangeId.v ?? 0,
      lessThan(3),
    );

    // Back online: every record comes.
    readSource.offline = false;
    await synchronizer.sync();
    expect(await _store.count(db), 3);
    expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 3);

    await synchronizer.close();
    await syncedSdb.close();
    await source.close();
  });
}
