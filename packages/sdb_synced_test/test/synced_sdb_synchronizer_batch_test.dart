import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:tekaly_synced_db_common/synced_db_common_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart'
    as fb;

// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

/// A Firestore source counting its puts.
class _CountingSource extends SyncedSourceFirestore {
  var putCount = 0;
  var batchSizes = <int>[];

  _CountingSource() : super(firestore: fb.newFirestoreMemory(), rootPath: null);

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record) {
    putCount++;
    return super.putSourceRecord(record);
  }

  @override
  Future<List<CvSyncedSourceRecord>> putSourceRecords(
    List<CvSyncedSourceRecord> records,
  ) {
    batchSizes.add(records.length);
    return super.putSourceRecords(records);
  }
}

void main() {
  cvAddConstructor(DbEntity.new);
  group('synced_sdb_synchronizer_batch', () {
    test('the local changes go up in batches', () async {
      var source = _CountingSource();
      var syncedSdb = SyncedSdb.newInMemory(options: sdbEntityOptions);
      var sync = SyncedSdbSynchronizer(db: syncedSdb, source: source);
      var db = await syncedSdb.database;
      for (var i = 0; i < 25; i++) {
        await (sdbEntityStoreRef.record('$i').cv()..name.v = 'name $i').put(db);
      }
      expect(await sync.sync(), SyncedSyncStat(remoteCreatedCount: 25));
      expect(source.batchSizes, [25]);
      expect(source.putCount, 0);
      expect((await source.getMetaInfo())!.lastChangeId.v, 25);

      // A smaller step: several batches.
      sync.stepLimitUp = 10;
      for (var i = 0; i < 25; i++) {
        await (sdbEntityStoreRef.record('$i').cv()..name.v = 'other $i').put(
          db,
        );
      }
      expect(await sync.sync(), SyncedSyncStat(remoteUpdatedCount: 25));
      expect(source.batchSizes, [25, 10, 10, 5]);
      expect((await source.getMetaInfo())!.lastChangeId.v, 50);

      // Another device gets them all.
      var otherSdb = SyncedSdb.newInMemory(options: sdbEntityOptions);
      var otherSync = SyncedSdbSynchronizer(db: otherSdb, source: source);
      expect(await otherSync.sync(), SyncedSyncStat(localCreatedCount: 25));
      var other = await sdbEntityStoreRef.findRecords(await otherSdb.database);
      expect(
        other.map((record) => record.name.v),
        unorderedEquals([for (var i = 0; i < 25; i++) 'other $i']),
      );
      await otherSync.close();
      await otherSdb.close();
      await sync.close();
      await syncedSdb.close();
    });
  });
}
