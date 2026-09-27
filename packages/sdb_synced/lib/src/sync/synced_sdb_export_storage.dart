import 'dart:convert';

import 'package:path/path.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb_export.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_firebase_storage/storage.dart';

/// Cache control of an export file: it never changes once written.
const syncedSdbStorageExportCacheControl =
    'public, max-age=31536000, immutable';

/// Cache control of the export meta file: revalidated on each read.
const syncedSdbStorageExportMetaCacheControl = 'no-cache';

/// Content type of an export file (JSON Lines).
const syncedSdbStorageExportContentType = 'application/x-ndjson';

/// Where a tekaly export lives in Storage:
/// * `<rootPath>/export_meta<suffix>.json`, the meta pointing to the current
///   export;
/// * `<rootPath>/export_<changeId>.jsonl`, one file per published change id.
class SyncedSdbStorageExportContext {
  /// Storage.
  final FirebaseStorage storage;

  /// Bucket name, the default bucket when null.
  final String? bucketName;

  /// Folder of the export files.
  final String rootPath;

  /// Optional meta basename suffix (`export_meta<suffix>.json`).
  final String? metaBasenameSuffix;

  /// Cache control of the export files, public and immutable by default.
  ///
  /// Pass null (or a `private` value) for an export that is not public.
  final String? exportCacheControl;

  /// Cache control of the meta file, `no-cache` by default.
  final String? metaCacheControl;

  /// Creates the storage export context.
  SyncedSdbStorageExportContext({
    required this.storage,
    this.bucketName,
    required this.rootPath,
    this.metaBasenameSuffix,
    this.exportCacheControl = syncedSdbStorageExportCacheControl,
    this.metaCacheControl = syncedSdbStorageExportMetaCacheControl,
  });

  /// The bucket of the export files.
  Bucket get bucket => storage.bucket(bucketName);

  /// The meta file.
  File get metaFile => bucket.file(
    url.join(rootPath, syncedDbExportMetaFileName(suffix: metaBasenameSuffix)),
  );

  /// The export file of [changeId].
  File exportFile(int changeId) =>
      bucket.file(url.join(rootPath, syncedDbExportFileName(changeId)));

  /// The published meta, null when nothing was published yet.
  Future<SyncedDbExportMeta?> readExportMeta() async {
    var file = metaFile;
    if (!await file.exists()) {
      return null;
    }
    return SyncedDbExportMeta()..fromMap(await fetchExportMeta());
  }

  /// Reads the meta, a [SyncedDbSynchronizerFetchExportMeta] for
  /// `SyncedSdbSynchronizerFromTekalyExport`.
  Future<Map<String, Object?>> fetchExportMeta() async =>
      (jsonDecode(await metaFile.readAsString()) as Map)
          .cast<String, Object?>();

  /// Reads the export of [changeId], a [SyncedDbSynchronizerFetchExport] for
  /// `SyncedSdbSynchronizerFromTekalyExport`.
  Future<String> fetchExport(int changeId) =>
      exportFile(changeId).readAsString();

  /// The change ids of the export files in [rootPath] (not in its sub
  /// folders), in ascending order.
  Future<List<int>> listExportChangeIds() async {
    var dir = url.dirname(exportFile(0).name);
    var changeIds = <int>[];
    GetFilesOptions? query = GetFilesOptions(
      // The whole bucket when at its root.
      prefix: dir == '.' ? null : '$dir/',
      autoPaginate: false,
    );
    while (query != null) {
      var response = await bucket.getFiles(query);
      for (var file in response.files) {
        var changeId = syncedDbExportFileNameChangeId(url.basename(file.name));
        if (changeId != null && exportFile(changeId).name == file.name) {
          changeIds.add(changeId);
        }
      }
      query = response.nextQuery;
    }
    return changeIds..sort();
  }

  /// Deletes the old export files: the [keep] most recent ones (highest
  /// change ids) and the one the meta points to are kept.
  ///
  /// [keep] is at least 2 (the default), so that a reader that read the
  /// previous meta just before a publish can still fetch its file.
  ///
  /// Returns the change ids of the deleted files, in ascending order.
  Future<List<int>> pruneExports({int keep = 2}) async {
    if (keep < 2) {
      throw ArgumentError.value(keep, 'keep', 'must be at least 2');
    }
    var changeIds = await listExportChangeIds();
    var metaChangeId = (await readExportMeta())?.lastChangeId.v;
    var kept = {...changeIds.reversed.take(keep), ?metaChangeId};
    var deleted = [
      for (var changeId in changeIds)
        if (!kept.contains(changeId)) changeId,
    ];
    for (var changeId in deleted) {
      await exportFile(changeId).delete();
    }
    return deleted;
  }

  @override
  String toString() =>
      'SyncedSdbStorageExportContext(${bucketName ?? '<default>'}/$rootPath)';
}

/// Result of [SyncedSdbExportStorageExt.exportDatabaseToStorage].
class SyncedSdbStorageExportResult {
  /// The change id of the published export.
  final int changeId;

  /// False when Storage already had this export: nothing was written.
  final bool written;

  /// Size in bytes of the export file written, null when nothing was written.
  final int? exportSize;

  /// Creates the export result.
  SyncedSdbStorageExportResult({
    required this.changeId,
    required this.written,
    this.exportSize,
  });

  @override
  String toString() => {
    'changeId': changeId,
    'written': written,
    if (exportSize != null) 'exportSize': exportSize,
  }.toString();
}

/// Storage export helper.
extension SyncedSdbExportStorageExt on SyncedSdb {
  /// Publishes the database to Storage as a tekaly export (see
  /// [SyncedSdbStorageExportContext] for the files).
  ///
  /// `export_<changeId>.jsonl` is written first, then the meta pointing to
  /// it, so a reader never gets a meta pointing to a missing file.
  ///
  /// When the published meta already has the change id (and source version)
  /// of the database, nothing is written: an unchanged republish costs one
  /// meta read. The change id only moves on a sync, so publish a synced
  /// database (a server side mirror of the source): local changes not synced
  /// yet are not published until the next sync.
  Future<SyncedSdbStorageExportResult> exportDatabaseToStorage({
    required SyncedSdbStorageExportContext exportContext,
  }) async {
    var syncMeta = await getSyncMetaInfo();
    var published = await exportContext.readExportMeta();
    if (published != null &&
        published.lastChangeId.v == (syncMeta?.lastChangeId.v ?? 0) &&
        published.sourceVersion.v == syncMeta?.sourceVersion.v) {
      return SyncedSdbStorageExportResult(
        changeId: published.lastChangeId.v!,
        written: false,
      );
    }

    var exportInfo = await exportInMemory();
    var exportMeta = exportInfo.metaInfo;
    var changeId = exportMeta.lastChangeId.v!;
    var bytes = utf8.encode(sdbExportLinesToJsonlString(exportInfo.data));
    await exportContext
        .exportFile(changeId)
        .upload(
          bytes,
          options: StorageUploadFileOptions(
            contentType: syncedSdbStorageExportContentType,
            cacheControl: exportContext.exportCacheControl,
          ),
        );
    await exportContext.metaFile.upload(
      utf8.encode(jsonEncode(exportMeta.toMap())),
      options: StorageUploadFileOptions(
        contentType: 'application/json',
        cacheControl: exportContext.metaCacheControl,
      ),
    );
    return SyncedSdbStorageExportResult(
      changeId: changeId,
      written: true,
      exportSize: bytes.length,
    );
  }
}
