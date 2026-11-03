import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';

// ignore: depend_on_referenced_packages
import 'package:test/test.dart';

/// A memory source running [onGetMetaInfo] once, at its next meta info read
/// (the start of the sync down).
class _MetaHookSource extends SyncedSourceMemory {
  Future<void> Function()? onGetMetaInfo;

  @override
  Future<CvMetaInfo?> getMetaInfo() async {
    var hook = onGetMetaInfo;
    onGetMetaInfo = null;
    await hook?.call();
    return await super.getMetaInfo();
  }
}

void main() {
  cvAddConstructor(DbEntity.new);
  group('synced_sdb_synchronizer_before_sync_up', () {
    late _MetaHookSource source;
    late SyncedSdb syncedSdb;
    late SyncedSdbSynchronizer sync;

    setUp(() {
      source = _MetaHookSource();
      syncedSdb = SyncedSdb.newInMemory(options: sdbEntityOptions);
      sync = SyncedSdbSynchronizer(db: syncedSdb, source: source);
    });
    tearDown(() async {
      await sync.close();
      await syncedSdb.close();
      await source.close();
    });

    Future<int?> lastChangeId() async =>
        (await source.getMetaInfo())?.lastChangeId.v;

    test('what an action writes goes up with the same push', () async {
      var db = await syncedSdb.database;
      var calls = <String>[];
      sync.addBeforeSyncUpAction(() async {
        calls.add('first');
        var record = await sdbEntityStoreRef.record('1').get(db);
        if (record != null && record.name.v == 'draft') {
          await (record..name.v = 'final').put(db);
        }
      });
      sync.addBeforeSyncUpAction(() async {
        calls.add('second');
      });
      await (sdbEntityStoreRef.record('1').cv()..name.v = 'draft').put(db);
      expect(await sync.sync(), SyncedSyncStat(remoteCreatedCount: 1));
      expect(calls, ['first', 'second']);
      // A single change, already final.
      expect(await lastChangeId(), 1);
      var sourceRecord = await source.getSourceRecord(
        SyncedDataSourceRef(store: sdbEntityStoreRef.name, key: '1'),
      );
      expect(sourceRecord!.record.v!.value.v!['name'], 'final');

      // Run before each push, nothing dirty included.
      expect(await sync.sync(), SyncedSyncStat());
      expect(calls, ['first', 'second', 'first', 'second']);
    });

    test('run before the push of a first full sync too', () async {
      var db = await syncedSdb.database;
      var calls = 0;
      sync.addBeforeSyncUpAction(() async {
        calls++;
        var record = await sdbEntityStoreRef.record('1').get(db);
        if (record != null && record.name.v == 'draft') {
          await (record..name.v = 'final').put(db);
        }
      });
      // Added after the sync up: the full sync down meets it and pushes it.
      source.onGetMetaInfo = () async {
        await (sdbEntityStoreRef.record('1').cv()..name.v = 'draft').put(db);
      };
      expect(await sync.sync(), SyncedSyncStat(remoteCreatedCount: 1));
      expect(calls, 2);
      expect(await lastChangeId(), 1);
      var sourceRecord = await source.getSourceRecord(
        SyncedDataSourceRef(store: sdbEntityStoreRef.name, key: '1'),
      );
      expect(sourceRecord!.record.v!.value.v!['name'], 'final');
    });

    test('an action error does not stop the push', () async {
      var db = await syncedSdb.database;
      var calls = 0;
      sync.addBeforeSyncUpAction(() async {
        calls++;
        throw StateError('failing action');
      });
      await (sdbEntityStoreRef.record('1').cv()..name.v = 'name').put(db);
      expect(await sync.sync(), SyncedSyncStat(remoteCreatedCount: 1));
      expect(calls, 1);
      expect(await lastChangeId(), 1);
    });

    test('remove', () async {
      var calls = 0;
      var remove = sync.addBeforeSyncUpAction(() async {
        calls++;
      });
      await sync.sync();
      expect(calls, 1);
      remove();
      await sync.sync();
      expect(calls, 1);
    });

    test('not run by a read-only synchronizer', () async {
      var readOnly = SyncedSdbSynchronizer(
        db: SyncedSdb.newInMemory(options: sdbEntityOptions),
        readSource: source,
      );
      var calls = 0;
      readOnly.addBeforeSyncUpAction(() async {
        calls++;
      });
      await readOnly.sync();
      expect(calls, 0);
      await readOnly.close();
    });
  });
}
