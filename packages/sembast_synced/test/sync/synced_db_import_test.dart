import 'dart:convert';

import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_app_sync.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

/// A synced db with its own meta and sync record stores (like FestenaoDb).
class _CustomStoresDb extends SyncedDbBase {
  _CustomStoresDb() {
    databaseFactory = newDatabaseFactoryMemory();
  }

  @override
  final dbSyncMetaStoreRef = cvStringStoreFactory.store<DbSyncMetaInfo>(
    'custom_meta',
  );
  @override
  final dbSyncRecordStoreRef = cvIntStoreFactory.store<DbSyncRecord>(
    'custom_record',
  );
  @override
  late final Future<Database> rawDatabase = databaseFactory.openDatabase(
    'custom.db',
  );
}

var _myStore = stringMapStoreFactory.store('my_store');
var _otherStore = stringMapStoreFactory.store('other_store');
var _localPrefixStore = stringMapStoreFactory.store('local_prefs');
var _localSuffixStore = stringMapStoreFactory.store('cache_local');

enum _ImportPath { tekaly, legacy, appSync }

Future<void> _import(
  SyncedDb importer,
  SyncedDb exporter,
  _ImportPath path,
) async {
  switch (path) {
    case _ImportPath.tekaly:
      await importer.importFromMemory(
        exportInfo: await exporter.exportInMemory(),
      );
    case _ImportPath.legacy:
      await importer.importFromMemoryLegacy(
        exportInfo: await exporter.exportInMemoryLegacy(),
      );
    case _ImportPath.appSync:
      var exportInfo = await exporter.exportInMemoryLegacy();
      await SyncedDbAppSyncExport(
        importer,
        fetcher: SyncedDbAppSyncExportFetcher(
          (_) async =>
              exportInfo.data.map((line) => jsonEncode(line)).join('\n'),
          () async => exportInfo.metaInfo.toMap(),
        ),
      ).sync();
  }
}

/// Exporter with a synced record and local records.
Future<SyncedDb> _newExporter({SyncedDb? syncedDb}) async {
  var exporter = syncedDb ?? SyncedDb.newInMemory();
  var db = await exporter.database;
  await _myStore.record('a').put(db, {'v': 1});
  await _localPrefixStore.record('device').put(db, {'who': 'exporter'});
  await SyncedDbSynchronizer(
    db: exporter,
    source: newInMemorySyncedSourceMemory(),
  ).sync();
  return exporter;
}

void main() {
  for (var path in _ImportPath.values) {
    group('import ${path.name}', () {
      test('keeps the importer local stores', () async {
        var exporter = await _newExporter();
        var importer = SyncedDb.newInMemory();
        var db = await importer.database;
        await _localPrefixStore.record('device').put(db, {'who': 'importer'});
        await _localSuffixStore.record('k').put(db, {'cached': true});

        await _import(importer, exporter, path);
        expect(await _myStore.record('a').get(db), {'v': 1});
        // Local stores are neither replaced nor emptied.
        expect(await _localPrefixStore.record('device').get(db), {
          'who': 'importer',
        });
        expect(await _localSuffixStore.record('k').get(db), {'cached': true});
        expect((await importer.getSyncMetaInfo())!.lastChangeId.v, 1);
      });

      test('keeps the pending sync records', () async {
        var exporter = await _newExporter();
        var importer = SyncedDb.newInMemory();
        var db = await importer.database;
        await _myStore.record('b').put(db, {'v': 2});
        await _myStore.record('a').put(db, {'v': 3});
        await _myStore.record('a').delete(db);
        var syncRecords = await importer.getSyncRecords();
        expect(syncRecords, hasLength(2));

        await _import(importer, exporter, path);
        expect(
          (await importer.getSyncRecords()).map((record) => record.toMap()),
          syncRecords.map((record) => record.toMap()),
        );
      });

      test('fresh db, nothing marked dirty', () async {
        var exporter = await _newExporter();
        var importer = SyncedDb.newInMemory();
        await _import(importer, exporter, path);
        expect(await importer.getSyncRecords(), isEmpty);
        expect(await importer.onDirty().first, isFalse);
        expect(await _myStore.record('a').get(await importer.database), {
          'v': 1,
        });
      });

      test('synced store missing from the export is emptied', () async {
        var exporter = await _newExporter();
        var importer = SyncedDb.newInMemory();
        var db = await importer.database;
        await importer.syncTransaction((txn) async {
          await _otherStore.record('x').put(txn, {'old': true});
        });
        await _import(importer, exporter, path);
        expect(await _otherStore.record('x').get(db), isNull);
        expect(await _myStore.record('a').get(db), {'v': 1});
      });

      test('custom meta store', () async {
        var exporter = await _newExporter(syncedDb: _CustomStoresDb());
        var importer = _CustomStoresDb();
        await _import(importer, exporter, path);
        var meta = await importer.getSyncMetaInfo();
        expect(meta!.lastChangeId.v, 1);
        expect(await _myStore.record('a').get(await importer.database), {
          'v': 1,
        });
      });
    });
  }

  test('legacy export without local stores', () async {
    var exporter = await _newExporter();
    var exportInfo = await exporter.exportInMemoryLegacy();
    var stores = exportInfo.data
        .whereType<Map>()
        .map((line) => line['store'])
        .nonNulls
        .toList();
    // The meta store is kept for the importers that read it.
    expect(stores, ['local_sync_meta', 'my_store']);
  });
}
