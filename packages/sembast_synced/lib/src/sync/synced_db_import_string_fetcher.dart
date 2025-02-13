import 'dart:convert';
import 'package:cv/cv.dart';

import '../../synced_db.dart';

/// Export file name
String getExportFileName(int changeId) => 'export_$changeId.jsonl';

/// Export meta file name
String getExportMetaFileName({String? suffix}) =>
    'export_meta${suffix ?? ''}.json';

abstract class SyncedDbStringFetcher {
  Future<String> getString(String path);
}

class SyncedDbStringFetcherContext {
  final SyncedDbStringFetcher fetcher;

  /// Optional meta basename suffix
  final String? metaBasenameSuffix;

  SyncedDbStringFetcherContext({
    required this.fetcher,
    required this.metaBasenameSuffix,
  });
}

extension SyncedDbFetcherExt on SyncedDb {
  Future<void> importDatabaseFromFetcher({
    /// Destination folder (import export.jsonl and export_meta.json)
    required SyncedDbStringFetcherContext fetcherContext,
  }) async {
    var fetcher = fetcherContext.fetcher;
    await fetchAndImport(
      fetchExport: (int changeId) async {
        return fetcher.getString(getExportFileName(changeId));
      },
      fetchExportMeta: () async {
        var exportString = await fetcher.getString(
          getExportMetaFileName(suffix: fetcherContext.metaBasenameSuffix),
        );
        var map = jsonDecode(exportString) as Map;
        return asModel(map);
      },
    );
  }
}
