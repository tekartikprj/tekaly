import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart'
    show SdbSyncMetaInfo;
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

/// Serves the files of [bucket] at `https://cdn.test/<path>` like Cloud
/// Storage: an ETag (the md5), `304 Not Modified` when it matches
/// `If-None-Match`. Every request is logged in [requests] as
/// `<status> <path>`.
http.Client _storageHttpClient(Bucket bucket, List<String> requests) =>
    MockClient((request) async {
      var path = request.url.path.substring(1);
      var file = bucket.file(path);
      if (!await file.exists()) {
        requests.add('404 $path');
        return http.Response('', 404);
      }
      var metadata = await file.getMetadata();
      var etag = '"${metadata.md5Hash}"';
      var headers = {
        'etag': etag,
        if (metadata.cacheControl != null)
          'cache-control': metadata.cacheControl!,
      };
      if (request.headers['if-none-match'] == etag) {
        requests.add('304 $path');
        return http.Response('', 304, headers: headers);
      }
      requests.add('200 $path');
      // No charset: the fetcher must decode utf8 itself.
      return http.Response.bytes(
        await file.readAsBytes(),
        200,
        headers: {...headers, 'content-type': metadata.contentType!},
      );
    });

void main() {
  group('SyncedSdbHttpExportFetcher', () {
    test('meta revalidated with its etag', () async {
      var server = SyncedSdb.newInMemory(options: _newOptions());
      var serverDb = await server.database;
      var serverSynchronizer = SyncedSdbSynchronizer(
        db: server,
        source: newInMemorySyncedSourceMemory(),
      );
      var exportContext = SyncedSdbStorageExportContext(
        storage: newStorageMemory(),
        rootPath: 'published/project_1',
      );
      await _itemStoreRef.record('a').put(serverDb, {'name': 'Aé'});
      await serverSynchronizer.sync();
      await server.exportDatabaseToStorage(exportContext: exportContext);

      var requests = <String>[];
      var fetcher = SyncedSdbHttpExportFetcher.folder(
        client: _storageHttpClient(exportContext.bucket, requests),
        folderUri: Uri.parse('https://cdn.test/published/project_1'),
      );
      expect(
        fetcher.metaUri.toString(),
        'https://cdn.test/published/project_1/export_meta.json',
      );
      var audience = SyncedSdb.newInMemory(options: _newOptions());
      var audienceDb = await audience.database;
      var audienceSynchronizer = SyncedSdbSynchronizerFromTekalyExport(
        audience,
        fetchExport: fetcher.fetchExport,
        fetchExportMeta: fetcher.fetchExportMeta,
      );

      await audienceSynchronizer.sync();
      expect(await _itemStoreRef.record('a').getValue(audienceDb), {
        'name': 'Aé',
      });
      expect(requests, [
        '200 published/project_1/export_meta.json',
        '200 published/project_1/export_1.jsonl',
      ]);

      // Nothing published since: a 304 with no body, nothing imported.
      requests.clear();
      await audienceSynchronizer.sync();
      await audienceSynchronizer.sync();
      expect(requests, [
        '304 published/project_1/export_meta.json',
        '304 published/project_1/export_meta.json',
      ]);
      expect(fetcher.metaNotModifiedCount, 2);

      // A new publish: a new meta, then its export file.
      await _itemStoreRef.record('b').put(serverDb, {'name': 'B'});
      await serverSynchronizer.sync();
      await server.exportDatabaseToStorage(exportContext: exportContext);
      requests.clear();
      await audienceSynchronizer.sync();
      expect(requests, [
        '200 published/project_1/export_meta.json',
        '200 published/project_1/export_2.jsonl',
      ]);
      expect(await _itemStoreRef.record('b').getValue(audienceDb), {
        'name': 'B',
      });

      // A source migration: the file name holds the new source version.
      await server.setSyncMetaInfo(
        serverDb,
        SdbSyncMetaInfo()
          ..lastChangeId.v = 1
          ..sourceVersion.v = 2,
      );
      await server.exportDatabaseToStorage(exportContext: exportContext);
      requests.clear();
      await audienceSynchronizer.sync();
      expect(requests, [
        '200 published/project_1/export_meta.json',
        '200 published/project_1/export_v2_1.jsonl',
      ]);
      expect((await audience.getSyncMetaInfo())!.sourceVersion.v, 2);

      await serverSynchronizer.close();
      await server.close();
      await audience.close();
    });

    test('missing meta', () async {
      var requests = <String>[];
      var fetcher = SyncedSdbHttpExportFetcher.folder(
        client: _storageHttpClient(newStorageMemory().bucket(), requests),
        folderUri: Uri.parse('https://cdn.test/none/'),
      );
      await expectLater(
        fetcher.fetchExportMeta(),
        throwsA(isA<http.ClientException>()),
      );
      expect(requests, ['404 none/export_meta.json']);
    });

    test('firebaseStorage urls', () {
      var fetcher = SyncedSdbHttpExportFetcher.firebaseStorage(
        client: MockClient((_) async => http.Response('', 404)),
        bucket: 'my-bucket',
        rootPath: 'published/project_1',
      );
      expect(
        fetcher.metaUri.toString(),
        'https://firebasestorage.googleapis.com/v0/b/my-bucket/o/'
        'published%2Fproject_1%2Fexport_meta.json?alt=media',
      );
      expect(
        fetcher.exportUri(3, sourceVersion: 2).toString(),
        'https://firebasestorage.googleapis.com/v0/b/my-bucket/o/'
        'published%2Fproject_1%2Fexport_v2_3.jsonl?alt=media',
      );
      fetcher = SyncedSdbHttpExportFetcher.firebaseStorage(
        client: MockClient((_) async => http.Response('', 404)),
        bucket: 'my-bucket',
        rootPath: 'p',
        endpoint: Uri.parse('http://127.0.0.1:9199'),
      );
      expect(
        fetcher.metaUri.toString(),
        'http://127.0.0.1:9199/v0/b/my-bucket/o/p%2Fexport_meta.json?alt=media',
      );
    });
  });
}
