/*
/// Http import context
class SyncedDbHttpImportContext {
  /// Http factory
  final HttpFactory httpFactory;

  /// Root path
  final Uri rootUri;

  /// Optional meta basename suffix
  final String? metaBasenameSuffix;

  SyncedDbHttpImportContext(
      {required this.httpFactory,
      required this.rootUri,
      required this.metaBasenameSuffix});
}

/// Expor helper
extension SyncedDbImportHttpExt on SyncedDb {
  /// Export
  /// * `export_meta<suffix>.json`
  /// * `export_<changeId>.jsonl`
  Future<void> importDatabaseFromHttp(
      {required SyncedDbHttpImportContext importContext}) async {
    await fetchAndImport(
        fetchExport: (int changeId) async {},
        fetchExportMeta: () async {
          if (importContext is SyncedDbStorageExportContext) {
            var storage = importContext.storage;
            var bucket = importContext.bucketName;
            var rootPath = importContext.rootPath;
            var suffix = importContext.metaBasenameSuffix;
            return asModel(jsonDecode(await storage
                .bucket(bucket)
                .file(url.join(rootPath, getExportMetaFileName(suffix: suffix)))
                .readAsString()) as Map);
          } else {
            throw UnimplementedError();
          }
        });
  }
}
*/
