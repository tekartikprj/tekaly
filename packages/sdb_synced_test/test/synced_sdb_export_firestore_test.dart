import 'package:dev_test/test.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced_test/synced_sdb_test_common.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekaly_synced_db_common_test/synced_source_firestore_test_common.dart';

/// A synchronized sdb database and the source it syncs with, both in memory.
class _ExportContext {
  final SyncedSdb syncedSdb;
  final SyncedSource source;
  final SyncedSdbSynchronizer synchronizer;

  _ExportContext({
    required this.syncedSdb,
    required this.source,
    required this.synchronizer,
  });

  Future<void> dispose() async {
    await synchronizer.close();
    await Future.wait([source.close(), syncedSdb.close()]);
  }
}

void main() {
  cvAddConstructor(DbEntity.new);

  /// A database synced with [source], holding a couple of entities.
  Future<_ExportContext> setupContext(SyncedSource source) async {
    var syncedSdb = SyncedSdb.newInMemory(options: sdbEntityOptions);
    var db = await syncedSdb.database;
    await (sdbEntityStoreRef.record('a1').cv()
          ..name.v = 'test1'
          ..counter.v = 1
          ..timestamp.v = SdbTimestamp.parse('2024-01-02T03:04:05.000Z'))
        .put(db);
    await (sdbEntityStoreRef.record('a2').cv()
          ..name.v = 'test2'
          ..counter.v = 2)
        .put(db);
    var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
    await synchronizer.sync();
    return _ExportContext(
      syncedSdb: syncedSdb,
      source: source,
      synchronizer: synchronizer,
    );
  }

  group('synced sdb and firestore source export', () {
    test('both sides export the same records', () async {
      var context = await setupContext(newInMemorySyncedSourceFirestore());
      try {
        var localExport = await context.syncedSdb.exportInMemory();
        var sourceExport = await context.source.exportInMemory();

        // The records match, which is the whole point: what the database
        // holds is what the source holds.
        expect(localExport.findContentDifference(sourceExport), isNull);
        expect(localExport.matchesContent(sourceExport), isTrue);
        expect(localExport.recordsByStore, sourceExport.recordsByStore);
        expect(localExport.storeNames, [dbEntityStoreName]);
        expect(sourceExport.storeNames, [dbEntityStoreName]);
        expect(localExport.recordCount, 2);

        // And the content lines agree too, both sides sorting by store then
        // key.
        expect(localExport.contentLines, sourceExport.contentLines);
        expect(localExport.contentLines.first, syncedDbExportHeaderLine);

        // The meta line is each side's own bookkeeping, which is why the
        // comparison leaves it out.
        expect(localExport.metaInfo.lastChangeId.v, 2);
        expect(sourceExport.metaInfo.lastChangeId.v, 2);
      } finally {
        await context.dispose();
      }
    });

    test('the memory source agrees with the firestore one', () async {
      var firestoreContext = await setupContext(
        newInMemorySyncedSourceFirestore(),
      );
      var memoryContext = await setupContext(newInMemorySyncedSourceMemory());
      try {
        var firestoreExport = await firestoreContext.source.exportInMemory();
        var memoryExport = await memoryContext.source.exportInMemory();
        expect(firestoreExport.findContentDifference(memoryExport), isNull);
      } finally {
        await firestoreContext.dispose();
        await memoryContext.dispose();
      }
    });

    test('a change on one side shows on both after a sync', () async {
      var context = await setupContext(newInMemorySyncedSourceFirestore());
      try {
        var db = await context.syncedSdb.database;
        await (sdbEntityStoreRef.record('a3').cv()..name.v = 'test3').put(db);
        await context.synchronizer.sync();

        var localExport = await context.syncedSdb.exportInMemory();
        var sourceExport = await context.source.exportInMemory();
        expect(localExport.recordCount, 3);
        expect(localExport.findContentDifference(sourceExport), isNull);
      } finally {
        await context.dispose();
      }
    });

    test('a deleted record is gone from both exports', () async {
      var context = await setupContext(newInMemorySyncedSourceFirestore());
      try {
        var db = await context.syncedSdb.database;
        await sdbEntityStoreRef.record('a1').delete(db);
        await context.synchronizer.sync();

        var localExport = await context.syncedSdb.exportInMemory();
        var sourceExport = await context.source.exportInMemory();
        expect(localExport.recordsByStore[dbEntityStoreName]!.keys, ['a2']);
        expect(localExport.findContentDifference(sourceExport), isNull);
      } finally {
        await context.dispose();
      }
    });

    test('an export says what differs when it does', () async {
      var context = await setupContext(newInMemorySyncedSourceFirestore());
      try {
        var localExport = await context.syncedSdb.exportInMemory();
        // A change that was not synced: the database has it, the source does
        // not.
        var db = await context.syncedSdb.database;
        await (sdbEntityStoreRef.record('a4').cv()..name.v = 'test4').put(db);
        var changedExport = await context.syncedSdb.exportInMemory();

        expect(
          changedExport.findContentDifference(localExport),
          '$dbEntityStoreName/a4 is missing on the other side',
        );
        expect(
          localExport.findContentDifference(changedExport),
          '$dbEntityStoreName/a4 is only on the other side',
        );
      } finally {
        await context.dispose();
      }
    });
  });
}
