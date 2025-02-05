import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/sembast_synced.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase_rest.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_import_string_fetcher.dart';
import 'package:tekartik_firebase_storage_rest/storage_json.dart';
import 'package:tekartik_http/http_client.dart';

import 'import_common.dart';

/// Export file name
String getExportFileName(int changeId) => 'export_$changeId.jsonl';

/// Export meta file name
String getExportMetaFileName({String? suffix}) =>
    'export_meta${suffix ?? ''}.json';

class _StorageFetcher implements SyncedDbStringFetcher {
  final FirebaseStorage storage;
  final String? bucket;
  final String rootPath;

  _StorageFetcher(
      {required this.storage, required this.bucket, required this.rootPath});

  @override
  Future<String> getString(String path) async {
    return await storage
        .bucket(bucket)
        .file(url.join(rootPath, path))
        .readAsString();
  }
}

class _UnauthenticatedStorageFetcher implements SyncedDbStringFetcher {
  final UnauthenticatedStorageApi api;
  final String rootPath;
  _UnauthenticatedStorageFetcher({required this.api, required this.rootPath});

  Client? client;
  @override
  Future<String> getString(String path) async {
    var noCache = '&v=${DateTime.now().millisecondsSinceEpoch}';
    var filePath = url.join(rootPath, path);
    // devPrint('Getting $metaPath');
    var client = this.client ??= api.client ?? Client();
    return await httpClientRead(client, httpMethodGet,
        Uri.parse('${api.getMediaUrl(filePath)}$noCache'),
        responseEncoding: utf8);
  }
}

/// Expor helper
extension SyncedDbImportStorageExt on SyncedDb {
  /// Export
  /// * `export_meta<suffix>.json`
  /// * `export_<changeId>.jsonl`
  Future<void> importDatabaseFromStorage(
      {required SyncedDbStorageImportContext importContext}) async {
    if (importContext is SyncedDbStorageExportContext) {
      var fetcher = _StorageFetcher(
          storage: importContext.storage,
          bucket: importContext.bucketName,
          rootPath: importContext.rootPath);
      await importDatabaseFromFetcher(
          fetcherContext: SyncedDbStringFetcherContext(
              fetcher: fetcher,
              metaBasenameSuffix: importContext.metaBasenameSuffix));
    } else {
      throw UnimplementedError();
    }
  }

  Future<void> importDatabaseFromUnauthenticatedStorage(
      {required SyncedDbUnauthenticatedStorageApiImportContext
          importContext}) async {
    var fetcher = _UnauthenticatedStorageFetcher(
      api: importContext.storageApi,
      rootPath: importContext.rootPath,
    );
    await importDatabaseFromFetcher(
        fetcherContext: SyncedDbStringFetcherContext(
            fetcher: fetcher,
            metaBasenameSuffix: importContext.metaBasenameSuffix));
  }
}
