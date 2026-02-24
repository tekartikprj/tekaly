import 'package:cv/cv.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:sembast/utils/sembast_import_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_export.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_synchronizer.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_source_export.dart';
import 'package:tekartik_app_http/app_http.dart';

import 'import_common.dart';
import 'synced_source_firestore.dart';

/// Sync either from an export or from firestore
abstract class SyncedDbAppSync {
  /// Synced db
  SyncedDb get db;

  /// synchronized (down)
  Future<void> sync();
}

/// Synced db app sync mixin
mixin SyncedDbAppSyncMixin implements SyncedDbAppSync {
  @override
  late SyncedDb db;
}

/// Fetch export meta
typedef SyncedDbAppSyncFetchExportMeta =
    Future<Map<String, Object?>> Function();

/// Fetch export
typedef SyncedDbAppSyncFetchExport = Future<String> Function(int changeId);

/// Synced db http export fetcher
class SyncedDbHttpExportFetcher implements SyncedDbAppSyncExportFetcher {
  /// Http client factory
  late HttpClientFactory httpClientFactory;

  /// Base uri
  final Uri baseUri;

  @override
  SyncedDbAppSyncFetchExport get fetchExport => _fetchExport;

  @override
  SyncedDbAppSyncFetchExportMeta get fetchExportMeta => _fetchExportMeta;

  Client? _client;

  /// Client
  Client get client => _client ??= httpClientFactory.newClient();

  /// Constructor
  SyncedDbHttpExportFetcher({
    required this.baseUri,
    HttpClientFactory? httpClientFactory,
  }) {
    this.httpClientFactory = httpClientFactory ?? httpClientFactoryUniversal;
  }

  /// Export meta uri
  Uri get exportMetaUri => baseUri.replace(
    pathSegments: [...baseUri.pathSegments, syncedDbExportMetaFilename],
  );

  /// Export uri
  Uri get exportUri => baseUri.replace(
    pathSegments: [...baseUri.pathSegments, syncedDbExportFilename],
  );

  Future<String> _fetchExport(int changeId) async {
    try {
      var data = await client.read(exportUri);
      return data;
    } catch (e, st) {
      // ignore: avoid_print
      print('No data in assets $e $st');
      rethrow;
    }
  }

  Future<Model> _fetchExportMeta() async {
    try {
      var map = jsonDecode(await client.read(exportMetaUri)) as Map;
      return map.cast<String, Object?>();
    } catch (e, st) {
      // ignore: avoid_print
      print('No data in assets $e $st');
      rethrow;
    }
  }

  /// Dispose
  void dispose() {
    _client?.close();
    _client = null;
  }
}

/// Synced db app sync export fetcher
class SyncedDbAppSyncExportFetcher {
  /// Constructor
  SyncedDbAppSyncExportFetcher(this.fetchExport, this.fetchExportMeta);

  /// Fetch export
  final SyncedDbAppSyncFetchExport fetchExport;

  /// Fetch export meta
  final SyncedDbAppSyncFetchExportMeta fetchExportMeta;
}

/// Sync from export
class SyncedDbAppSyncExport
    with SyncedDbAppSyncMixin
    implements SyncedDbAppSync {
  /// Constructor
  SyncedDbAppSyncExport(SyncedDb db, {required this.fetcher}) {
    this.db = db;
  }

  /// Only sync if fetch export does not return null
  final SyncedDbAppSyncExportFetcher fetcher;

  @override
  Future<void> sync() async {
    var meta = await db.getSyncMetaInfo();
    var newMeta = SyncedDbExportMeta()
      ..fromMap(await fetcher.fetchExportMeta());
    var newLastChangeId = newMeta.lastChangeId.v!;
    if ((meta?.sourceVersion.v != newMeta.sourceVersion.v) ||
        (newMeta.lastChangeId.v! > (meta?.lastChangeId.v ?? 0))) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('importing data $newMeta');
      }
      var data = await fetcher.fetchExport(newLastChangeId);
      var sourceDb = await importDatabaseAny(
        data,
        newDatabaseFactoryMemory(),
        'export',
      );
      await databaseMerge(await db.database, sourceDatabase: sourceDb);
      await sourceDb.close();
    }
  }
}

/// Sync from firestore
class SyncedDbAppSyncFirestore
    with SyncedDbAppSyncMixin
    implements SyncedDbAppSync {
  /// Constructor
  SyncedDbAppSyncFirestore(SyncedDb db, this.sourceFirestore) {
    this.db = db;
  }

  /// Source firestore
  final SyncedSourceFirestore sourceFirestore;

  @override
  Future<void> sync() async {
    var sync = SyncedDbSynchronizer(db: db, source: sourceFirestore);
    var stat = await sync.syncDown();
    if (debugSyncedSync) {
      // ignore: avoid_print
      print(stat);
    }
  }
}
