import 'dart:convert';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

final _store = SdbStoreRef<String, SdbModel>('my_store');
final _localStore = SdbStoreRef<String, SdbModel>('local_prefs');

final _schema = SdbDatabaseSchema(
  stores: [
    _store.schema(),
    _localStore.schema(),
    ...syncedSdbMetaSchema.stores,
  ],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);

SyncedSdb _newSyncedSdb() => SyncedSdb.newInMemory(options: _newOptions());

/// A synced sdb extending the exported base class.
class _MySyncedSdb extends SyncedSdbBase {
  _MySyncedSdb({required super.options});

  @override
  late final rawDatabase = newSdbFactoryMemory().openDatabase(
    'my_synced.db',
    options: options.openDatabaseOptions,
  );

  @override
  ScvStoreRef<String, SdbSyncMetaInfo> get scvSyncMetaStoreRef =>
      sdbSyncMetaStoreRef;

  @override
  ScvStoreRef<int, SdbSyncRecord> get scvSyncRecordStoreRef =>
      sdbSyncRecordStoreRef;
}

String _export(int lastChangeId, Map<String, Map<String, Object?>> stores) {
  var lines = <Object>[
    {'tekaly_export': 1, 'version': 1},
    {'lastChangeId': lastChangeId},
    for (var entry in stores.entries) ...[
      {'store': entry.key},
      for (var record in entry.value.entries) [record.key, record.value],
    ],
  ];
  return lines.map(jsonEncode).join('\n');
}

Future<void> _import(
  SyncedSdb db,
  int lastChangeId,
  Map<String, Map<String, Object?>> stores,
) => db.fetchAndImport(
  fetchExport: (_) async => _export(lastChangeId, stores),
  fetchExportMeta: () async => {'lastChangeId': lastChangeId},
);

void main() {
  group('synced_sdb_regression', () {
    test('sync down skips the stores unknown to the local schema', () async {
      var source = SyncedSourceMemory();
      Future<void> put(String store, String key) => source.putSourceRecord(
        CvSyncedSourceRecord()
          ..record.v = (CvSyncedSourceRecordData()
            ..store.v = store
            ..key.v = key
            ..value.v = {'a': 1}),
      );
      await put('my_store', 'k1');
      // Newer schema
      await put('other_store', 'k2');
      // Local data of another client
      await put('local_prefs', 'k3');
      var syncedSdb = _newSyncedSdb();
      var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);
      await synchronizer.sync();
      var db = await syncedSdb.database;
      expect((await _store.findRecords(db)).map((r) => r.key), ['k1']);
      expect(await _localStore.findRecords(db), isEmpty);
      expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 3);
      await synchronizer.close();
      await syncedSdb.close();
    });

    test('import ignores unknown and local stores, no dirty record', () async {
      var syncedSdb = _newSyncedSdb();
      var db = await syncedSdb.database;
      await _localStore.record('theme').put(db, {'dark': true});
      await _import(syncedSdb, 1, {
        'my_store': {
          'a': {'v': 1},
        },
        'other_store': {
          'b': {'v': 2},
        },
        'local_prefs': {
          'theme': {'dark': false},
        },
      });
      expect(await _store.record('a').getValue(db), {'v': 1});
      expect(await _localStore.record('theme').getValue(db), {'dark': true});
      // Imported records are not marked dirty (no sync up of the import)
      expect(await syncedSdb.txnGetDirtySyncRecords(db), isEmpty);
      expect((await syncedSdb.getSyncMetaInfo())!.lastChangeId.v, 1);
      await syncedSdb.close();
    });

    test('import notifies the sync meta info', () async {
      var syncedSdb = _newSyncedSdb();
      await _import(syncedSdb, 1, {
        'my_store': {
          'a': {'v': 1},
        },
      });
      var lastChangeIds = <int?>[];
      var subscription = syncedSdb.onSyncMetaInfo().listen(
        (meta) => lastChangeIds.add(meta?.lastChangeId.v),
      );
      await syncedSdb.onSyncMetaInfo().firstWhere(
        (meta) => meta?.lastChangeId.v == 1,
      );
      await _import(syncedSdb, 5, {
        'my_store': {
          'a': {'v': 2},
        },
      });
      await syncedSdb.onSyncMetaInfo().firstWhere(
        (meta) => meta?.lastChangeId.v == 5,
      );
      expect(lastChangeIds.last, 5);
      await subscription.cancel();
      await syncedSdb.close();
    });

    test('export import keeps maps looking like encoded values', () async {
      var value = <String, Object?>{
        'ts': {r'$timestamp': 'not a date'},
        'timestamp': SdbTimestamp(1, 2000),
      };
      var target = _newSyncedSdb();
      await _import(target, 1, {
        'my_store': {
          'a': jsonDecode(jsonEncode(syncedDbValueToJsonEncodable(value))),
        },
      });
      expect(await _store.record('a').getValue(await target.database), value);
      await target.close();
    });

    test('close while the database is opening', () async {
      var syncedSdb = SyncedSdb(
        name: 'closed_while_opening.db',
        databaseFactory: newSdbFactoryMemory(),
        options: _newOptions(),
      );
      var dbFuture = syncedSdb.database;
      await syncedSdb.close();
      var db = await dbFuture;
      await expectLater(
        _store.record('a').put(db, {'v': 1}),
        throwsA(anything),
      );
    });

    test('extends SyncedSdbBase', () async {
      var syncedSdb = _MySyncedSdb(options: _newOptions());
      await syncedSdb.database;
      expect(await syncedSdb.getSyncMetaInfo(), isNull);
      expect(syncedSdb.syncedStoreNames, ['my_store']);
      await syncedSdb.close();
    });
  });
}
