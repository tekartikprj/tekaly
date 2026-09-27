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
/// * `<rootPath>/export_<changeId>.jsonl`, one file per published change
///   id (`export_v<sourceVersion>_<changeId>.jsonl` when the source has a
///   version, see [syncedDbExportFileName]).
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

  /// The export file of [changeId] and [sourceVersion].
  File exportFile(int changeId, {int? sourceVersion}) => bucket.file(
    url.join(
      rootPath,
      syncedDbExportFileName(changeId, sourceVersion: sourceVersion),
    ),
  );

  /// The export file a [meta] points to.
  File exportFileOf(SyncedDbExportMeta meta) =>
      exportFile(meta.lastChangeId.v ?? 0, sourceVersion: meta.sourceVersion.v);

  /// The published meta, null when nothing was published yet.
  Future<SyncedDbExportMeta?> readExportMeta() async {
    var file = metaFile;
    if (!await file.exists()) {
      return null;
    }
    return SyncedDbExportMeta()..fromMap(await fetchExportMeta());
  }

  /// The meta read by the last [fetchExportMeta], whose source version
  /// [fetchExport] needs.
  SyncedDbExportMeta? _fetchedMeta;

  /// Reads the meta, a [SyncedDbSynchronizerFetchExportMeta] for
  /// `SyncedSdbSynchronizerFromTekalyExport`.
  Future<Map<String, Object?>> fetchExportMeta() async {
    var map = (jsonDecode(await metaFile.readAsString()) as Map)
        .cast<String, Object?>();
    _fetchedMeta = SyncedDbExportMeta()..fromMap(map);
    return map;
  }

  /// Reads the export of [changeId], a [SyncedDbSynchronizerFetchExport] for
  /// `SyncedSdbSynchronizerFromTekalyExport`.
  ///
  /// The file name also holds the source version, taken from the meta of
  /// [changeId] read by [fetchExportMeta] just before (the synchronizer
  /// order), otherwise from the published meta.
  Future<String> fetchExport(int changeId) async {
    var meta = _fetchedMeta;
    if (meta?.lastChangeId.v != changeId) {
      meta = await readExportMeta();
    }
    return exportFile(
      changeId,
      sourceVersion: meta?.sourceVersion.v,
    ).readAsString();
  }

  /// The export files in [rootPath] (not in its sub folders), oldest first:
  /// by source version then change id.
  Future<List<SyncedDbExportFileId>> listExportFileIds() async {
    var dir = url.dirname(exportFile(0).name);
    var fileIds = <SyncedDbExportFileId>[];
    GetFilesOptions? query = GetFilesOptions(
      // The whole bucket when at its root.
      prefix: dir == '.' ? null : '$dir/',
      autoPaginate: false,
    );
    while (query != null) {
      var response = await bucket.getFiles(query);
      for (var file in response.files) {
        var fileId = syncedDbExportFileNameParse(url.basename(file.name));
        if (fileId != null && _exportFileOfId(fileId).name == file.name) {
          fileIds.add(fileId);
        }
      }
      query = response.nextQuery;
    }
    return fileIds..sort(_compareFileIds);
  }

  File _exportFileOfId(SyncedDbExportFileId fileId) =>
      exportFile(fileId.changeId, sourceVersion: fileId.sourceVersion);

  /// Deletes the old export files: the [keep] most recent ones (highest
  /// source version, then highest change id) and the one the meta points to
  /// are kept.
  ///
  /// [keep] is at least 2 (the default), so that a reader that read the
  /// previous meta just before a publish can still fetch its file.
  ///
  /// Returns the deleted files, oldest first.
  Future<List<SyncedDbExportFileId>> pruneExports({int keep = 2}) async {
    if (keep < 2) {
      throw ArgumentError.value(keep, 'keep', 'must be at least 2');
    }
    var fileIds = await listExportFileIds();
    var meta = await readExportMeta();
    var kept = {
      ...fileIds.reversed.take(keep),
      if (meta != null)
        (
          changeId: meta.lastChangeId.v ?? 0,
          // null and 0 give the same file name.
          sourceVersion: (meta.sourceVersion.v ?? 0) == 0
              ? null
              : meta.sourceVersion.v,
        ),
    };
    var deleted = [
      for (var fileId in fileIds)
        if (!kept.contains(fileId)) fileId,
    ];
    for (var fileId in deleted) {
      await _exportFileOfId(fileId).delete();
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

  /// The source version of the published export.
  final int? sourceVersion;

  /// False when Storage already had this export: nothing was written.
  final bool written;

  /// Size in bytes of the export file written, null when nothing was written.
  final int? exportSize;

  /// Creates the export result.
  SyncedSdbStorageExportResult({
    required this.changeId,
    this.sourceVersion,
    required this.written,
    this.exportSize,
  });

  @override
  String toString() => {
    'changeId': changeId,
    if (sourceVersion != null) 'sourceVersion': sourceVersion,
    'written': written,
    if (exportSize != null) 'exportSize': exportSize,
  }.toString();
}

/// Storage export helper.
extension SyncedSdbExportStorageExt on SyncedSdb {
  /// Publishes the database to Storage as a tekaly export (see
  /// [SyncedSdbStorageExportContext] for the files).
  ///
  /// The export file (see [syncedDbExportFileName]) is written first, then
  /// the meta pointing to it, so a reader never gets a meta pointing to a
  /// missing file.
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
        sourceVersion: published.sourceVersion.v,
        written: false,
      );
    }

    var exportInfo = await exportInMemory();
    var exportMeta = exportInfo.metaInfo;
    var changeId = exportMeta.lastChangeId.v!;
    var bytes = utf8.encode(sdbExportLinesToJsonlString(exportInfo.data));
    await exportContext
        .exportFileOf(exportMeta)
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
      sourceVersion: exportMeta.sourceVersion.v,
      written: true,
      exportSize: bytes.length,
    );
  }
}

int _compareFileIds(SyncedDbExportFileId a, SyncedDbExportFileId b) {
  var result = (a.sourceVersion ?? 0).compareTo(b.sourceVersion ?? 0);
  return result != 0 ? result : a.changeId.compareTo(b.changeId);
}
