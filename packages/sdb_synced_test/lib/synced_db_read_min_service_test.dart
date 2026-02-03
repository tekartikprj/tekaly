// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'package:dev_test/test.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/sdb_synced.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'synced_sdb_synchronizer_test.dart';
import 'synced_sdb_test_common.dart';

void main() {
  group('min_service_in_memory', () {
    syncedDbReadMinServiceTests(setupNewInMemorySyncSdbTestsContext);
  });
}

void syncedDbReadMinServiceTests(
  Future<SyncSdbTestsContext> Function() setupContext,
) {
  cvAddConstructor(DbEntity.new);

  group('min service', () async {
    late SyncedSdbSynchronizer sync;

    late SyncedSource source;
    late SyncedSdb syncedDb;
    late SyncSdbTestsContext context;
    late SdbDatabase db;
    var record1 = dbEntityStoreRef.record('r1');
    late SyncedSdbReadMinService localService;
    late SyncedSdbReadMinService remoteService;
    setUp(() async {
      context = await setupContext();
      source = context.source;
      syncedDb = context.syncedSdb;
      sync = SyncedSdbSynchronizer(db: syncedDb, source: source);
      db = await syncedDb.database;
      localService = SyncedSdbReadMinService.syncedDb(syncedDb: syncedDb);
      remoteService = SyncedSdbReadMinService.syncedSource(
        syncedSource: source,
      );
    });
    tearDown(() async {
      /// Close first
      await sync.close();

      await context.dispose();
    });

    test('simple sync one record', () async {
      var localRecord = await localService.getRecordData(record1.rawRef);
      expect(localRecord, isNull);
      var timestamp = SyncedDbTimestamp(2, 3000);
      var expectedLocalMap = {
        'name': 'text1',
        'timestamp': timestamp.toDateTime(isUtc: true),
      };
      var insertedRecord = record1.cv()
        ..name.v = 'text1'
        ..timestamp.v = timestamp;
      expect(insertedRecord.toMap(), expectedLocalMap);
      expect(expectedLocalMap.cv<DbEntity>(), insertedRecord);
      await insertedRecord.put(db);
      localRecord = await localService.getRecordData(record1.rawRef);
      expect(localRecord!.cv<DbEntity>(), insertedRecord);
      print('localRecord: $localRecord');
      expect(localRecord, expectedLocalMap);
      print('Before remote read');

      var remoteRecordData = await remoteService.getRecordData(record1.rawRef);
      expect(remoteRecordData, isNull);

      var stat1 = await sync.sync();

      expect(stat1, SyncedSyncStat(remoteCreatedCount: 1));

      remoteRecordData = await remoteService.getRecordData(record1.rawRef);
      var expectedRemoteMap = {'name': 'text1', 'timestamp': timestamp};
      print('remoteRecord: $remoteRecordData');
      expect(remoteRecordData, expectedRemoteMap);
      var sdbData = mapSyncedDbToSdb(remoteRecordData!);
      expect(remoteRecordData.cv<DbEntity>().timestamp.v, isNull); // !!!
      expect(sdbData.cv<DbEntity>(), insertedRecord);
    });
  });
}
