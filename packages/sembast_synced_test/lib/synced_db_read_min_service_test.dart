// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member

import 'package:dev_test/test.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

import 'synced_db_synchronizer_test.dart';
import 'synced_db_test_common.dart';

void main() {
  group('min_service_in_memory', () {
    syncedDbReadMinServiceTests(setupNewInMemorySyncTestsContext);
  });
}

void syncedDbReadMinServiceTests(
  Future<SyncTestsContext> Function() setupContext,
) {
  cvAddConstructor(DbEntity.new);

  group('min service', () async {
    late SyncedDbSynchronizer sync;

    late SyncedSource source;
    late SyncedDb syncedDb;
    late SyncTestsContext context;
    late Database db;
    var record1 = dbEntityStoreRef.record('r1');
    late SyncedDbReadMinService localService;
    late SyncedDbReadMinService remoteService;
    setUp(() async {
      context = await setupContext();
      source = context.source;
      syncedDb = context.syncedDb;
      sync = SyncedDbSynchronizer(db: syncedDb, source: source);
      db = await syncedDb.database;
      localService = SyncedDbReadMinService.syncedDb(syncedDb: syncedDb);
      remoteService = SyncedDbReadMinService.syncedSource(syncedSource: source);
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
      var expectedMap = {'name': 'text1', 'timestamp': timestamp};
      await (record1.cv()
            ..name.v = 'text1'
            ..timestamp.v = timestamp)
          .put(db);
      localRecord = await localService.getRecordData(record1.rawRef);
      expect(localRecord, expectedMap);

      var remoteRecord = await remoteService.getRecordData(record1.rawRef);
      expect(remoteRecord, isNull);

      var stat1 = await sync.sync();

      expect(stat1, SyncedSyncStat(remoteCreatedCount: 1));

      remoteRecord = await remoteService.getRecordData(record1.rawRef);
      expect(remoteRecord, expectedMap);
    });
  });
}
