import 'dart:convert';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_storage.dart';
import 'package:tekartik_firebase_storage_fs/storage_fs.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

final _itemStoreRef = SdbStoreRef<String, SdbModel>('item');

final _schema = SdbDatabaseSchema(
  stores: [_itemStoreRef.schema(), ...syncedSdbMetaSchema.stores],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);

void main() {
  group('exportDatabaseToStorage', () {
    late SyncedSdb server;
    late SyncedSdbSynchronizer serverSynchronizer;
    late SyncedSdbStorageExportContext exportContext;

    setUp(() {
      server = SyncedSdb.newInMemory(options: _newOptions());
      serverSynchronizer = SyncedSdbSynchronizer(
        db: server,
        source: newInMemorySyncedSourceMemory(),
      );
      exportContext = SyncedSdbStorageExportContext(
        storage: newStorageMemory(),
        rootPath: 'published/project_1',
      );
    });

    tearDown(() async {
      await server.close();
    });

    Future<List<String>> publishedFileNames() async {
      var response = await exportContext.bucket.getFiles(
        GetFilesOptions(prefix: 'published/'),
      );
      return response.files.map((file) => file.name).toList()..sort();
    }

    test('round trip', () async {
      var db = await server.database;
      await _itemStoreRef.record('a').put(db, {'name': 'A'});
      await _itemStoreRef.record('b').put(db, {'name': 'B'});
      await serverSynchronizer.sync();

      var result = await server.exportDatabaseToStorage(
        exportContext: exportContext,
      );
      expect(result.written, isTrue);
      var changeId = result.changeId;
      expect(changeId, 2);
      expect(await publishedFileNames(), [
        'published/project_1/export_2.jsonl',
        'published/project_1/export_meta.json',
      ]);
      var exportMetadata = await exportContext.exportFile(2).getMetadata();
      expect(exportMetadata.cacheControl, syncedSdbStorageExportCacheControl);
      expect(exportMetadata.contentType, syncedSdbStorageExportContentType);
      expect(exportMetadata.size, result.exportSize);
      var metaMetadata = await exportContext.metaFile.getMetadata();
      expect(metaMetadata.cacheControl, 'no-cache');
      expect(metaMetadata.contentType, 'application/json');
      expect((await exportContext.readExportMeta())!.lastChangeId.v, changeId);

      // The audience fills an empty db from the export.
      var audience = SyncedSdb.newInMemory(options: _newOptions());
      var audienceSynchronizer = SyncedSdbSynchronizerFromTekalyExport(
        audience,
        fetchExport: exportContext.fetchExport,
        fetchExportMeta: exportContext.fetchExportMeta,
      );
      await audienceSynchronizer.sync();
      var audienceDb = await audience.database;
      expect(await _itemStoreRef.record('a').getValue(audienceDb), {
        'name': 'A',
      });
      expect(await _itemStoreRef.record('b').getValue(audienceDb), {
        'name': 'B',
      });
      expect((await audience.getSyncMetaInfo())!.lastChangeId.v, 2);

      // An unchanged republish writes nothing.
      result = await server.exportDatabaseToStorage(
        exportContext: exportContext,
      );
      expect(result.written, isFalse);
      expect(result.changeId, 2);
      expect(result.exportSize, isNull);
      expect(
        (await exportContext.metaFile.getMetadata()).dateUpdated,
        metaMetadata.dateUpdated,
      );

      // One change gives a new export file, the old one stays as is.
      await _itemStoreRef.record('a').delete(db);
      await _itemStoreRef.record('c').put(db, {'name': 'C'});
      await serverSynchronizer.sync();
      result = await server.exportDatabaseToStorage(
        exportContext: exportContext,
      );
      expect(result.written, isTrue);
      expect(result.changeId, greaterThan(changeId));
      expect(
        await publishedFileNames(),
        [
          'published/project_1/export_2.jsonl',
          'published/project_1/export_${result.changeId}.jsonl',
          'published/project_1/export_meta.json',
        ]..sort(),
      );
      expect(
        (await exportContext.exportFile(2).getMetadata()).dateUpdated,
        exportMetadata.dateUpdated,
      );

      await audienceSynchronizer.sync();
      expect(await _itemStoreRef.record('a').getValue(audienceDb), isNull);
      expect(await _itemStoreRef.record('b').getValue(audienceDb), {
        'name': 'B',
      });
      expect(await _itemStoreRef.record('c').getValue(audienceDb), {
        'name': 'C',
      });
      expect(
        (await audience.getSyncMetaInfo())!.lastChangeId.v,
        result.changeId,
      );
      await audience.close();
    });

    test('never synced', () async {
      var result = await server.exportDatabaseToStorage(
        exportContext: exportContext,
      );
      expect(result.written, isTrue);
      expect(result.changeId, 0);
      expect(jsonDecode(await exportContext.metaFile.readAsString()), {
        'lastChangeId': 0,
      });
      expect(
        await exportContext.fetchExport(0),
        '{"tekaly_export":1,"version":1}\n{"lastChangeId":0}\n',
      );

      // Local changes do not move the change id: not published before a sync.
      var db = await server.database;
      await _itemStoreRef.record('a').put(db, {'name': 'A'});
      result = await server.exportDatabaseToStorage(
        exportContext: exportContext,
      );
      expect(result.written, isFalse);
      await serverSynchronizer.sync();
      result = await server.exportDatabaseToStorage(
        exportContext: exportContext,
      );
      expect(result.written, isTrue);
      expect(result.changeId, 1);
    });

    test('private export, meta suffix and bucket', () async {
      var storage = newStorageMemory();
      await storage.bucket('private_bucket').create();
      exportContext = SyncedSdbStorageExportContext(
        storage: storage,
        bucketName: 'private_bucket',
        rootPath: 'backup',
        metaBasenameSuffix: '_v2',
        exportCacheControl: null,
        metaCacheControl: null,
      );
      var db = await server.database;
      await _itemStoreRef.record('a').put(db, {'name': 'A'});
      await serverSynchronizer.sync();
      await server.exportDatabaseToStorage(exportContext: exportContext);

      var bucket = storage.bucket('private_bucket');
      var exportFile = bucket.file('backup/export_1.jsonl');
      var metaFile = bucket.file('backup/export_meta_v2.json');
      expect((await exportFile.getMetadata()).cacheControl, isNull);
      expect((await metaFile.getMetadata()).cacheControl, isNull);
      expect(jsonDecode(await metaFile.readAsString()), {
        'lastChangeId': 1,
        'lastTimestamp': isNotNull,
      });
    });
  });
}
