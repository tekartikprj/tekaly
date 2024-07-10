import 'package:sembast/timestamp.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:test/test.dart';

import 'synced_db_test.dart';
import 'synced_source_test.dart';

var syncedStoreNames = [dbEntityStoreName];
void main() {
  group('synced_db_source_sync_memory_test', () {
    Future<SyncTestsContext> setupContext() async {
//    setUp(() async {
      return SyncTestsContext()
        ..syncedDb = SyncedDb.newInMemory(syncedStoreNames: syncedStoreNames)
        ..source = newInMemorySyncedSourceMemory();
    }

    //  });
    syncTests(setupContext);
  });
}

class SyncTestsContext {
  late SyncedSource source;
  late SyncedDb syncedDb;
}

void syncTests(Future<SyncTestsContext> Function() setupContext) {
  cvAddConstructor(DbEntity.new);
  group('synced_db_source_sync_firestore_test', () {
    late SyncedDbSourceSync sync;
    late SyncedSource source;
    late SyncedDb syncedDb;
    setUp(() async {
      var context = await setupContext();
      source = context.source;
      syncedDb = context.syncedDb;
      sync = SyncedDbSourceSync(db: syncedDb, source: source);
    });
    test('syncNone', () async {
      var stat = await sync.sync();
      expect(stat, SyncedSyncStat());
    });

    test('syncOneAddToRemote', () async {
      expect(await syncedDb.getSyncRecords(), isEmpty);
      var db = await syncedDb.database;
      await (dbEntityStoreRef.record('a1').cv()
            ..name.v = 'test1'
            ..timestamp.v = Timestamp(1, 1000))
          .put(db);
      var syncRecords = await syncedDb.getSyncRecords();
      expect(syncRecords.map((r) => r.toMap()), [
        {'store': 'entity', 'key': 'a1', 'dirty': true}
      ]);
      var stat = await sync.syncUp();
      syncRecords = await syncedDb.getSyncRecords();
      var syncRecord = syncRecords.first;
      expect(syncRecord.syncId.v, isNotNull);
      expect(syncRecord.syncChangeId.v, isNotNull);
      expect(syncRecord.syncTimestamp.v, isNotNull);
      expect(syncRecords.map((r) => r.toMap()), [
        {
          'store': 'entity',
          'key': 'a1',
          'dirty': false,
          'deleted': false,
          'syncTimestamp': syncRecord.syncTimestamp.v,
          'syncId': syncRecord.syncId.v,
          'syncChangeId': 1,
        }
      ]);
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
      var sourceRecord = (await source
          .getSourceRecord(SyncedDataSourceRef(store: 'entity', key: 'a1')))!;
      expect(
          sourceRecord,
          SyncedSourceRecord()
            ..syncId.v = sourceRecord.syncId.v
            ..syncTimestamp.v = sourceRecord.syncTimestamp.v
            ..syncChangeId.v = 1
            ..record.v = (SyncedSourceRecordData()
              ..store.v = dbEntityStoreRef.name
              ..key.v = 'a1'
              ..deleted.v = false
              ..value.v = {'name': 'test1', 'timestamp': Timestamp(1, 1000)}));
      var sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 1});
      // Sync again
      stat = await sync.syncUp(fullSync: true);

      sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 1});
      expect(stat, SyncedSyncStat());
    });
    test('syncOneDeleteToRemote', () async {
      expect(await syncedDb.getSyncRecords(), isEmpty);
      var db = await syncedDb.database;
      var recordRef = dbEntityStoreRef.record('a1');
      await (recordRef.cv()
            ..name.v = 'test1'
            ..timestamp.v = Timestamp(1, 1000))
          .put(db);
      expect(await sync.sync(), SyncedSyncStat(remoteUpdatedCount: 1));
      await recordRef.delete(db);
      var syncRecords = await syncedDb.getSyncRecords();
      expect(syncRecords.first.deleted.v, isTrue);
      expect(syncRecords.first.dirty.v, isTrue);

      expect(await sync.sync(), SyncedSyncStat(remoteDeletedCount: 1));
    });
    test('syncOneUntrackedToRemote', () async {
      expect(await syncedDb.getSyncRecords(), isEmpty);
      var db = await syncedDb.database;
      await (dbEntityStoreRef.record('a1').cv()..name.v = 'test1').put(db);
      var syncRecords = await syncedDb.getSyncRecords();
      expect(syncRecords, isNotEmpty);
      await syncRecords.delete(db);
      expect(await syncedDb.getSyncRecords(), isEmpty);

      var stat = await sync.syncUp();
      syncRecords = await syncedDb.getSyncRecords();
      if (syncRecords.isNotEmpty) {
        var syncRecord = syncRecords.first;
        expect(syncRecord.syncId.v, isNotNull);
        expect(syncRecord.syncChangeId.v, isNotNull);
        expect(syncRecord.syncTimestamp.v, isNotNull);
        expect(syncRecords.map((r) => r.toMap()), [
          {
            'store': 'entity',
            'key': 'a1',
            'dirty': false,
            'deleted': false,
            'syncTimestamp': syncRecord.syncTimestamp.v,
            'syncId': syncRecord.syncId.v,
            'syncChangeId': 1,
          }
        ]);
        expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
        var sourceRecord = (await source
            .getSourceRecord(SyncedDataSourceRef(store: 'entity', key: 'a1')))!;
        expect(
            sourceRecord,
            SyncedSourceRecord()
              ..syncId.v = sourceRecord.syncId.v
              ..syncTimestamp.v = sourceRecord.syncTimestamp.v
              ..syncChangeId.v = 1
              ..record.v = (SyncedSourceRecordData()
                ..store.v = dbEntityStoreRef.name
                ..key.v = 'a1'
                ..deleted.v = false
                ..value.v = {'name': 'test1'}));
        var sourceMeta = (await source.getMetaInfo())!;
        expect(sourceMeta.toMap(), {'lastChangeId': 1});
      }
      // Sync again
      stat = await sync.syncUp();
      expect(stat, SyncedSyncStat());
      if (syncRecords.isNotEmpty) {
        var sourceMeta = (await source.getMetaInfo())!;
        expect(sourceMeta.toMap(), {'lastChangeId': 1});
      }
    });

    test('syncOneToRemoteBasic', () async {
      var db = await syncedDb.database;
      expect(await syncedDb.getSyncRecords(), isEmpty);
      var storeName = 'entity';

      await (dbEntityStoreRef.record('a1').cv()..name.v = 'test1').put(db);
      var syncRecords = await syncedDb.getSyncRecords();
      expect(syncRecords.map((r) => r.toMap()), [
        {'store': 'entity', 'key': 'a1', 'dirty': true}
      ]);
      var stat = await sync.syncUp();
      syncRecords = await syncedDb.getSyncRecords();
      var syncRecord = syncRecords.first;
      expect(syncRecord.syncId.v, isNotNull);
      expect(syncRecord.syncChangeId.v, isNotNull);
      expect(syncRecord.syncTimestamp.v, isNotNull);
      expect(syncRecords.map((r) => r.toMap()), [
        {
          'store': storeName,
          'key': 'a1',
          'dirty': false,
          'deleted': false,
          'syncTimestamp': syncRecord.syncTimestamp.v,
          'syncId': syncRecord.syncId.v,
          'syncChangeId': 1,
        }
      ]);
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
      var sourceRecord = (await source
          .getSourceRecord(SyncedDataSourceRef(store: storeName, key: 'a1')))!;
      expect(
          sourceRecord,
          SyncedSourceRecord()
            ..syncId.v = sourceRecord.syncId.v
            ..syncTimestamp.v = sourceRecord.syncTimestamp.v
            ..syncChangeId.v = 1
            ..record.v = (SyncedSourceRecordData()
              ..store.v = storeName
              ..key.v = 'a1'
              ..deleted.v = false
              ..value.v = {'name': 'test1'}));
      var sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 1});
      // Sync again
      stat = await sync.syncUp();

      sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 1});
      expect(stat, SyncedSyncStat());
    });

    test('syncOneFromRemote', () async {
      var sourceRecord = (await source.putSourceRecord(SyncedSourceRecord()
        //..syncId.v = sourceRecord.syncId.v
        // ..syncTimestamp.v = sourceRecord.syncTimestamp.v
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..value.v = {'name': 'test1', 'timestamp': Timestamp(1, 1000)})))!;
      expect(sourceRecord.syncId.v, isNotNull);
      expect(sourceRecord.syncTimestamp.v, isNotNull);

      var sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 1});

      expect(await syncedDb.getSyncMetaInfo(), null);

      /// Full sync
      var stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localUpdatedCount: 1));

      var metaInfo = (await syncedDb.getSyncMetaInfo())!;
      expect(metaInfo.toMap(),
          {'lastChangeId': 1, 'lastTimestamp': metaInfo.lastTimestamp.v});

      /// again
      stat = await sync.syncDown();
      expect(stat, SyncedSyncStat());

      sourceRecord = (await source.getSourceRecord(
          SyncedDataSourceRef(store: dbEntityStoreRef.name, key: 'a1')))!;

      expect(await exportDatabaseLines(await syncedDb.database), [
        {'sembast_export': 1, 'version': 1},
        {'store': 'entity'},
        [
          'a1',
          {
            'name': 'test1',
            'timestamp': {'@Timestamp': Timestamp(1, 1000).toIso8601String()}
          }
        ],
        {'store': 'syncMeta'},
        [
          'info',
          {
            'lastTimestamp': {
              '@Timestamp': metaInfo.lastTimestamp.v!.toIso8601String()
            },
            'lastChangeId': 1
          }
        ],
        {'store': 'syncRecord'},
        [
          1,
          {
            'store': 'entity',
            'key': 'a1',
            'deleted': false,
            'syncId': sourceRecord.syncId.v!,
            'syncTimestamp': {
              '@Timestamp': sourceRecord.syncTimestamp.v!.toIso8601String()
            }
          }
        ]
      ]);
    });

    test('syncOneWithDiacritic', () async {
      // debugWebServices = devWarning(true);
      var db = await syncedDb.database;
      expect(await syncedDb.getSyncRecords(), isEmpty);
      var ref = dbEntityStoreRef.record('diacritic');
      await (ref.cv()..name.v = 'éà').put(db);
      await sync.sync();
      // Delete locally and global sync info
      await ref.delete(db);
      await syncedDb.clearAllSyncInfo(db);

      expect(await ref.get(db), isNull);
      // Sync again
      await sync.sync();
      expect((await ref.get(db))!.name.v, 'éà');
    });

    test('syncOneDeleteFromRemote', () async {
      // debugSyncedSync = devWarning(true);
      var db = await syncedDb.database;
      (await source.putSourceRecord(SyncedSourceRecord()
        //..syncId.v = sourceRecord.syncId.v
        // ..syncTimestamp.v = sourceRecord.syncTimestamp.v
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'dummy'
          ..deleted.v = true)))!; // no value
      var sourceRecord = (await source.putSourceRecord(SyncedSourceRecord()
        //..syncId.v = sourceRecord.syncId.v
        // ..syncTimestamp.v = sourceRecord.syncTimestamp.v
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..deleted.v = true)))!; //
      expect(
          (await source.getSourceRecord(sourceRecord.ref))!.record.v!.deleted.v,
          isTrue);
      expect(sourceRecord.syncId.v, isNotNull);
      expect(sourceRecord.syncTimestamp.v, isNotNull);

      var sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 2});

      /// Full sync
      var stat = await sync.syncDown();
      expect(stat, SyncedSyncStat());

      /// Create the record locally but clear the sync info
      var ref = dbEntityStoreRef.record('a1');
      await (ref.cv()..name.v = 'test1').put(db);
      var syncRecords = await syncedDb.getSyncRecords();
      expect(syncRecords.map((r) => r.toMap()), [
        {'store': 'entity', 'key': 'a1', 'dirty': true}
      ]);
      //await syncedDb.clearSyncRecords(db);
      await syncedDb.setSyncMetaInfo(db, DbSyncMetaInfo()..lastChangeId.v = 1);
      stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localDeletedCount: 1));
      expect((await syncedDb.getSyncMetaInfoLastChangeId()), 2);

      /// again
      stat = await sync.syncDown();
      expect(stat, SyncedSyncStat());
    });

    test('syncOneDeleteNoData', () async {
      // debugSyncedSync = devWarning(true);
      var db = await syncedDb.database;
      var ref = dbEntityStoreRef.record('a1');
      await (ref.cv()..name.v = 'test1').put(db);
      await sync.sync();

      // Delete locally and global sync info
      await ref.delete(db);
      await sync.sync();

      await syncedDb.clearAllSyncInfo(db);
      expect(await syncedDb.getSyncMetaInfoLastChangeId(), null);
      var stat = await sync.doSync();
      expect(stat, SyncedSyncStat());
      expect(await syncedDb.getSyncMetaInfoLastChangeId(), 2);
    });

    test('syncOneRawFromRemote', () async {
      var sourceRecord = (await source.putSourceRecord(SyncedSourceRecord()
        //..syncId.v = sourceRecord.syncId.v
        // ..syncTimestamp.v = sourceRecord.syncTimestamp.v
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..value.v = {'name': 'test1'})))!;
      expect(sourceRecord.syncId.v, isNotNull);
      expect(sourceRecord.syncTimestamp.v, isNotNull);

      var sourceMeta = (await source.getMetaInfo())!;
      expect(sourceMeta.toMap(), {'lastChangeId': 1});

      expect(await syncedDb.getSyncMetaInfo(), null);

      /// Full sync
      var stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localUpdatedCount: 1));

      expect((await dbEntityStoreRef.find(await syncedDb.database)),
          [dbEntityStoreRef.record('a1').cv()..name.v = 'test1']);
      var metaInfo = (await syncedDb.getSyncMetaInfo())!;
      expect(metaInfo.toMap(),
          {'lastChangeId': 1, 'lastTimestamp': metaInfo.lastTimestamp.v});

      /// again
      stat = await sync.syncDown();
      expect(stat, SyncedSyncStat());
    });

    test('syncUpdateToRemote', () async {
      var db = await syncedDb.database;
      var ref = dbEntityStoreRef.record('a1');
      await (ref.cv()..name.v = 'test1').put(db);
      var stat = await sync.syncUp();
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
      await (ref.cv()..name.v = 'test2').put(db);
      stat = await sync.syncUp();
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
      stat = await sync.syncUp();
      expect(stat, SyncedSyncStat());
    });

    test('syncUpdateFromRemote', () async {
      await source.putSourceRecord(SyncedSourceRecord()
        //..syncId.v = sourceRecord.syncId.v
        // ..syncTimestamp.v = sourceRecord.syncTimestamp.v
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..value.v = {'name': 'test1'}));

      /// Full sync
      var stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localUpdatedCount: 1));

      /// update
      await source.putSourceRecord(SyncedSourceRecord()
        //..syncId.v = sourceRecord.syncId.v
        // ..syncTimestamp.v = sourceRecord.syncTimestamp.v
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..value.v = {'name': 'test2'}));
      stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localUpdatedCount: 1));
    });

    test('putMetaInfo', () async {
      //if (source is SyncedSourceFirestore) {
      // debugSyncedSync = true;
      var meta = CvMetaInfoRecord()
        ..version.v = 1
        ..lastChangeId.v = 2
        ..minIncrementalChangeId.v = 3;
      var updatedMeta = await source.putMetaInfo(meta);
      expect(updatedMeta, meta);
      var readMeta = await source.getMetaInfo();
      expect(readMeta, meta);
    });

    test('newVersionSyncUpdateFromRemote', () async {
      //if (source is SyncedSourceFirestore) {
      // debugSyncedSync = true;
      await source.putMetaInfo(CvMetaInfoRecord()
        ..version.v = 1
        ..lastChangeId.v = 1
        ..minIncrementalChangeId.v = 0);
      await source.putRawRecord(SyncedSourceRecord()
        ..syncId.v = '1'
        ..syncChangeId.v = 1
        ..syncTimestamp.v = Timestamp(1, 0)
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..value.v = {'name': 'test1'}));

      var stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localUpdatedCount: 1));

      // We just change the version and the data
      await source.putMetaInfo(CvMetaInfoRecord()
        ..version.v = 2
        ..lastChangeId.v = 1
        ..minIncrementalChangeId.v = 0);
      expect((await source.getMetaInfo())!.toMap(),
          {'minIncrementalChangeId': 0, 'lastChangeId': 1, 'version': 2});
      await source.putRawRecord(SyncedSourceRecord()
        ..syncId.v = '1'
        ..syncChangeId.v = 1
        ..syncTimestamp.v = Timestamp(1, 0)
        ..record.v = (SyncedSourceRecordData()
          ..store.v = dbEntityStoreRef.name
          ..key.v = 'a1'
          ..value.v = {'name': 'test2'}));
      stat = await sync.syncDown();
      expect(stat, SyncedSyncStat(localUpdatedCount: 1));
    });

    test('syncOneToRemoteThenAnotherOne', () async {
      // debugSyncedSync = devWarning(true);
      var db = await syncedDb.database;
      await (dbEntityStoreRef.record('a2').cv()).put(db);
      var stat = await sync.sync();
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
      await (dbEntityStoreRef.record('a1').cv()).put(db);
      stat = await sync.sync();
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));
    });

    test('sync3Step2', () async {
      // debugSyncedSync = devWarning(true);
      var db = await syncedDb.database;
      await (dbEntityStoreRef.record('a1').cv()).put(db);
      await (dbEntityStoreRef.record('a2').cv()).put(db);
      await (dbEntityStoreRef.record('a3').cv()).put(db);
      sync.stepLimitUp = 2;
      sync.stepLimitDown = 2;
      var stat = await sync.doSync();
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 3));
      /*
      await (dbEntityStoreRef.record('a1').cv()).put(db);
      stat = await sync.sync();
      expect(stat, SyncedSyncStat(remoteUpdatedCount: 1));

       */
    });
  });
}
