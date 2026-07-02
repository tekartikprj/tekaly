import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_sembast_synced/src/api/secure_client.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source_api.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase_sim.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_sembast_synced/synced_source.dart';
import 'package:test/test.dart';

/// Creates a [SyncedSourceApi] backed by a fully in-memory simulated backend
/// (in-memory Firestore + in-memory http server), isolated from other
/// sources by using [target] both as sync target and as a unique function
/// name so tests can create several independent in-memory sources.
Future<SyncedSourceApi> newInMemorySyncedSourceApi({
  required String target,
}) async {
  firebaseSimContext = initFirebaseSimMemory();
  var apiService = SecureApiServiceBase(
    packageName: 'test.package',
    isLocal: true,
    app: 'test_app',
    appType: 'test_type',
    functionName: 'test_fn_$target',
    sembastDatabaseFactory: newDatabaseFactoryMemory(),
  );
  await apiService.initClient();
  return SyncedSourceApi(apiService: apiService, target: target);
}

void main() {
  Future<SyncedDb> setupBasicDb(SyncedSourceApi source) async {
    var syncedDb = SyncedDb.newInMemory();
    var db = await syncedDb.database;
    await stringMapStoreFactory.store('my_store').record('my_key').put(db, {
      'test': 123,
    });

    var synchronizer = SyncedDbSynchronizer(db: syncedDb, source: source);
    await synchronizer.sync();
    return syncedDb;
  }

  test('exportInMemory/importFromMemory through SyncedSourceApi', () async {
    var source = await newInMemorySyncedSourceApi(target: 'export-test');
    var syncedDb = await setupBasicDb(source);

    var exportInfo = await source.exportInMemory();
    var timestamp = exportInfo.metaInfo.lastTimestamp.v!;
    var expectedMeta = {'lastChangeId': 1, 'lastTimestamp': timestamp};
    var expectedData = [
      {'tekaly_export': 1, 'version': 1},
      {'lastChangeId': 1, 'lastTimestamp': timestamp},
      {'store': 'my_store'},
      [
        'my_key',
        {'test': 123},
      ],
    ];
    expect(exportInfo.metaInfo.toMap(), expectedMeta);
    expect(exportInfo.data, expectedData);
    await syncedDb.close();

    // Import into a fresh (empty) in-memory source.
    var otherSource = await newInMemorySyncedSourceApi(target: 'import-test');
    expect((await otherSource.getMetaInfo())?.lastChangeId.v, isNull);

    await otherSource.importFromMemory(exportInfo: exportInfo);

    // Re-exporting the imported source gives back the same records (the
    // timestamp differs since it is reassigned by the backend on import).
    var reExportInfo = await otherSource.exportInMemory();
    expect(reExportInfo.metaInfo.lastChangeId.v, 1);
    expect(reExportInfo.metaInfo.lastTimestamp.v, isNotNull);
    expect(reExportInfo.data.sublist(0, 1), expectedData.sublist(0, 1));
    expect(reExportInfo.data.sublist(2), expectedData.sublist(2));

    // Syncing a fresh local db from the imported source also gives back the
    // original content.
    var otherDb = SyncedDb.newInMemory();
    var otherSynchronizer = SyncedDbSynchronizer(
      db: otherDb,
      source: otherSource,
    );
    await otherSynchronizer.sync();
    var db = await otherDb.database;
    expect(
      await stringMapStoreFactory.store('my_store').record('my_key').get(db),
      {'test': 123},
    );
    await otherDb.close();
  });
}
