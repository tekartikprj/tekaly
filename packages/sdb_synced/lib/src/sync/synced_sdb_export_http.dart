import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';

/// Reads a tekaly export published with `exportDatabaseToStorage` over http
/// (Cloud Storage, Firebase Hosting, tkwhost, a CDN), for
/// `SyncedSdbSynchronizerFromTekalyExport`.
///
/// The meta is revalidated with its ETag: when it did not change, the server
/// answers `304 Not Modified` with no body and [fetchExportMeta] returns the
/// meta it already has, so the synchronizer imports nothing. Export files
/// never change, they are read once.
class SyncedSdbHttpExportFetcher {
  /// Http client.
  final http.Client client;

  /// The url of a file of the export folder.
  final Uri Function(String fileName) fileUri;

  /// Optional meta basename suffix (`export_meta<suffix>.json`).
  final String? metaBasenameSuffix;

  /// Reads the export files with [client] at [fileUri].
  SyncedSdbHttpExportFetcher({
    required this.client,
    required this.fileUri,
    this.metaBasenameSuffix,
  });

  /// Reads the export files in [folderUri] (`https://host/path/to/folder/`).
  factory SyncedSdbHttpExportFetcher.folder({
    required http.Client client,
    required Uri folderUri,
    String? metaBasenameSuffix,
  }) {
    var folder = folderUri.path.endsWith('/')
        ? folderUri
        : folderUri.replace(path: '${folderUri.path}/');
    return SyncedSdbHttpExportFetcher(
      client: client,
      fileUri: (fileName) => folder.resolve(fileName),
      metaBasenameSuffix: metaBasenameSuffix,
    );
  }

  /// Reads the export files in [rootPath] of [bucket] through the Firebase
  /// Storage download api (`<endpoint>/v0/b/<bucket>/o/<path>?alt=media`),
  /// which the Storage rules must let read.
  factory SyncedSdbHttpExportFetcher.firebaseStorage({
    required http.Client client,
    required String bucket,
    required String rootPath,
    String? metaBasenameSuffix,
    Uri? endpoint,
  }) {
    endpoint ??= Uri.parse('https://firebasestorage.googleapis.com');
    return SyncedSdbHttpExportFetcher(
      client: client,
      fileUri: (fileName) => endpoint!.replace(
        pathSegments: [
          ...endpoint.pathSegments.where((segment) => segment.isNotEmpty),
          'v0',
          'b',
          bucket,
          'o',
          url.join(rootPath, fileName),
        ],
        queryParameters: {'alt': 'media'},
      ),
      metaBasenameSuffix: metaBasenameSuffix,
    );
  }

  /// The url of the meta file.
  Uri get metaUri =>
      fileUri(syncedDbExportMetaFileName(suffix: metaBasenameSuffix));

  /// The url of the export file of [changeId] and [sourceVersion].
  Uri exportUri(int changeId, {int? sourceVersion}) =>
      fileUri(syncedDbExportFileName(changeId, sourceVersion: sourceVersion));

  Map<String, Object?>? _meta;
  String? _metaEtag;

  /// How many meta reads were answered `304 Not Modified`.
  var metaNotModifiedCount = 0;

  /// Reads the meta, a [SyncedDbSynchronizerFetchExportMeta] for
  /// `SyncedSdbSynchronizerFromTekalyExport`.
  Future<Map<String, Object?>> fetchExportMeta() async {
    var meta = _meta;
    var etag = _metaEtag;
    var response = await client.get(
      metaUri,
      headers: {if (meta != null && etag != null) 'if-none-match': etag},
    );
    if (response.statusCode == 304 && meta != null) {
      metaNotModifiedCount++;
      return meta;
    }
    _checkOk(response);
    meta = (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
        .cast<String, Object?>();
    _meta = meta;
    _metaEtag = response.headers['etag'];
    return meta;
  }

  /// Reads the export of [changeId], a [SyncedDbSynchronizerFetchExport] for
  /// `SyncedSdbSynchronizerFromTekalyExport`.
  ///
  /// Its file name holds the source version of the meta read by
  /// [fetchExportMeta] just before (the synchronizer order).
  Future<String> fetchExport(int changeId) async {
    var meta = _meta;
    if (meta == null || meta['lastChangeId'] != changeId) {
      meta = await fetchExportMeta();
    }
    var sourceVersion = (SyncedDbExportMeta()..fromMap(meta)).sourceVersion.v;
    var response = await client.get(
      exportUri(changeId, sourceVersion: sourceVersion),
    );
    _checkOk(response);
    // JSON Lines are utf8, whatever the content type says.
    return utf8.decode(response.bodyBytes);
  }

  void _checkOk(http.Response response) {
    if (response.statusCode != 200) {
      throw http.ClientException(
        'status ${response.statusCode}',
        response.request?.url,
      );
    }
  }

  @override
  String toString() => 'SyncedSdbHttpExportFetcher($metaUri)';
}
