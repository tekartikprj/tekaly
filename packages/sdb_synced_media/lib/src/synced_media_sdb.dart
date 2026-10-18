import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:meta/meta.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_app_media/mime_type.dart';

import 'synced_media_file.dart';

/// Exception class for errors related to the [SyncedMediaSdb].
class SyncedMediaSdbException implements Exception {
  /// Error message describing the exception.
  final String message;

  /// Constructor for creating a SyncedMediaSdbException with a specific message.
  SyncedMediaSdbException(this.message);

  @override
  String toString() => 'SyncedMediaSdbException: $message';
}

/// Local status of a media file (not synced), its id is the media id.
class SdbSyncedMediaFileStatus extends ScvStringRecordBase {
  /// Content present locally (1 or 0)
  final local = CvField<int>('local');

  /// Content present remotely (1 or 0)
  final remote = CvField<int>('remote');

  /// Deleted (1 or 0)
  final deleted = CvField<int>('deleted');

  /// Path of the local content, kept to clean it up once the media record is
  /// gone.
  final path = CvField<String>('path');

  /// Size of the local content.
  final size = CvField<int>('size');

  /// Last access of the local content (milliseconds since epoch, strictly
  /// increasing), 0 if never read (downloaded on sync).
  final accessed = CvField<int>('accessed');

  @override
  CvFields get fields => [local, remote, deleted, path, size, accessed];
}

/// Extension for [SdbSyncedMediaFileStatus] to provide boolean helpers.
extension SdbSyncedMediaFileStatusExt on SdbSyncedMediaFileStatus {
  /// Whether the file is present locally.
  bool get isLocal => local.v == 1;

  /// Whether the file is present remotely.
  bool get isRemote => remote.v == 1;

  /// Whether the file is marked as deleted.
  bool get isDeleted => deleted.v == 1;

  /// Set the local status.
  void setLocal(bool? local) => this.local.v = (local ?? false) ? 1 : 0;

  /// Set the remote status.
  void setRemote(bool? remote) => this.remote.v = (remote ?? false) ? 1 : 0;

  /// Set the deleted status.
  void setDeleted(bool? deleted) => this.deleted.v = (deleted ?? false) ? 1 : 0;
}

/// Status model
final sdbSyncedMediaFileStatusModel = SdbSyncedMediaFileStatus();

/// Media file record (synced), its id is the media id.
class SdbSyncedMediaFile extends ScvStringRecordBase {
  /// Media type (mime type)
  final type = CvField<String>('type');

  /// File size
  final size = CvField<int>('size');

  /// Original filename of the media file, for reference.
  final originalFilename = CvField<String>('filename');

  /// Relative path of the content, locally and remotely.
  final path = CvField<String>('path');

  /// Timestamp when the media file was created (local only)
  final createdTimestamp = CvField<SdbTimestamp>('createdTimestamp');

  /// Set by uploader once the content is in the source.
  final uploaded = CvField<bool>('uploaded');

  /// Mark as deleted, purged once deleted from the source.
  final deleted = CvField<bool>('deleted');

  /// Network url of the content, set on upload when the synchronizer
  /// `storeUrl` option is on and the source gives one.
  final url = CvField<String>('url');

  @override
  CvFields get fields => [
    type,
    size,
    originalFilename,
    path,
    createdTimestamp,
    uploaded,
    deleted,
    url,
  ];

  /// Content ref
  SyncedMediaFileRef get fileRef => SyncedMediaFileRef.fromPath(path.v!);

  /// To media file
  SyncedMediaFile toMediaFile() {
    return SyncedMediaFile(
      originalFilename: originalFilename.v!,
      path: path.v!,
      uid: id,
      type: type.v ?? filenameMimeType(originalFilename.v!),
      size: size.v,
    );
  }
}

/// Extension for [SdbSyncedMediaFile] to provide status helpers.
extension SdbSyncedMediaFileExt on SdbSyncedMediaFile {
  /// Whether the file is marked as deleted.
  bool get isDeleted => deleted.v ?? false;

  /// Whether the file has been uploaded.
  bool get isUploaded => uploaded.v ?? false;
}

/// Media model
final sdbSyncedMediaFileModel = SdbSyncedMediaFile();

/// The stores of a media database: the synced media records and their local
/// status.
///
/// The default names (`media` and `local_media_status`) match the festenao
/// media stores.
class SyncedMediaSdbStores {
  /// Index name of the status store
  static const statusIndexName = 'local_remote_deleted';

  /// Media records store, synced.
  final ScvStoreRef<String, SdbSyncedMediaFile> mediaStore;

  /// Status store, local, its name must start with `local_`.
  final ScvStoreRef<String, SdbSyncedMediaFileStatus> statusStore;

  /// Status index local/remote/deleted.
  late final statusIndex = statusStore.index3<int, int, int>(statusIndexName);

  /// Stores [mediaStoreName] and [statusStoreName] (defaults to
  /// `local_<mediaStoreName>_status`).
  SyncedMediaSdbStores({
    String mediaStoreName = 'media',
    String? statusStoreName,
  }) : mediaStore = ScvStoreRef<String, SdbSyncedMediaFile>(mediaStoreName),
       statusStore = ScvStoreRef<String, SdbSyncedMediaFileStatus>(
         statusStoreName ??
             '${SyncedSdb.unsyncedStoreNamePrefix}${mediaStoreName}_status',
       ) {
    if (!statusStore.name.startsWith(SyncedSdb.unsyncedStoreNamePrefix)) {
      throw ArgumentError.value(
        statusStoreName,
        'statusStoreName',
        'must start with ${SyncedSdb.unsyncedStoreNamePrefix}',
      );
    }
  }

  /// The store schemas, to add to the database schema.
  List<SdbStoreSchema> get schemaStores => [
    mediaStore.schema(),
    statusStore.schema(
      indexes: [
        statusIndex.schema(
          keyPath: [
            sdbSyncedMediaFileStatusModel.local.name,
            sdbSyncedMediaFileStatusModel.remote.name,
            sdbSyncedMediaFileStatusModel.deleted.name,
          ],
        ),
      ],
    ),
  ];

  /// Both stores.
  List<ScvStoreRef> get stores => [mediaStore, statusStore];
}

/// Default stores (`media`, `local_media_status`).
final syncedMediaSdbStoresDefault = SyncedMediaSdbStores();

/// Local cache stat.
class SyncedMediaCacheStat {
  /// Number of media contents present locally.
  final int count;

  /// Total size of the media contents present locally.
  final int size;

  /// Number of local contents not uploaded yet (never evicted).
  final int pendingCount;

  /// Local cache stat.
  const SyncedMediaCacheStat({
    required this.count,
    required this.size,
    this.pendingCount = 0,
  });

  @override
  int get hashCode => Object.hash(count, size, pendingCount);

  @override
  bool operator ==(Object other) =>
      other is SyncedMediaCacheStat &&
      other.count == count &&
      other.size == size &&
      other.pendingCount == pendingCount;

  @override
  String toString() =>
      'SyncedMediaCacheStat(count: $count, size: $size'
      '${pendingCount > 0 ? ', pending: $pendingCount' : ''})';
}

/// Media database, the metadata in sdb (synced media store + local status
/// store) and the contents in a file system.
///
/// It does not access the network, see `SyncedMediaSdbSynchronizer`.
class SyncedMediaSdb {
  /// File system of the local contents.
  final FileSystem fs;

  /// Database holding [stores].
  final SdbDatabase database;

  /// Stores.
  final SyncedMediaSdbStores stores;

  ScvStoreRef<String, SdbSyncedMediaFile> get _mediaStore => stores.mediaStore;

  ScvStoreRef<String, SdbSyncedMediaFileStatus> get _statusStore =>
      stores.statusStore;

  var _lastAccessed = 0;

  /// Media database on [database] (which schema includes the
  /// [SyncedMediaSdbStores.schemaStores] of [stores]), the contents in [fs].
  SyncedMediaSdb({
    required this.fs,
    required this.database,
    SyncedMediaSdbStores? stores,
  }) : stores = stores ?? syncedMediaSdbStoresDefault {
    cvAddConstructors([SdbSyncedMediaFile.new, SdbSyncedMediaFileStatus.new]);
  }

  /// Strictly increasing access time.
  int _nextAccessed() {
    var now = DateTime.now().millisecondsSinceEpoch;
    _lastAccessed = now > _lastAccessed ? now : _lastAccessed + 1;
    return _lastAccessed;
  }

  /// The local file of the content at [path] (relative), which must be valid
  /// (see [syncedMediaIsValidPath]): it comes from a synced record.
  File localFile(String path) {
    if (!syncedMediaIsValidPath(path)) {
      throw SyncedMediaSdbException('Invalid media path $path');
    }
    return fs.file(fs.path.normalize(path));
  }

  Future<void> _writeMediaFileBytes(String path, Uint8List bytes) async {
    var fsFile = localFile(path);
    await fsFile.parent.create(recursive: true);
    await fsFile.writeAsBytes(bytes);
  }

  Future<void> _deleteMediaFileBytes(String path) async {
    if (!syncedMediaIsValidPath(path)) {
      // Nothing was written there
      return;
    }
    var fsFile = localFile(path);
    try {
      await fsFile.delete();
    } on FileSystemException catch (_) {
      // Not found
    }
  }

  /// Adds a media file, written locally, to upload on the next
  /// synchronization.
  ///
  /// Returns the media id.
  Future<String> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  }) async {
    var uid = file.uid;
    var path = file.path;
    var size = file.size ?? bytes.length;

    /// First write the file
    await _writeMediaFileBytes(path, bytes);

    // Then add to db, we know it exists, locally only
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var mediaRecord = _mediaStore.record(uid).cv()
          ..createdTimestamp.value = SdbTimestamp.now()
          ..type.setValue(file.type)
          ..size.setValue(size)
          ..originalFilename.setValue(file.originalFilename)
          ..path.value = path;
        await mediaRecord.put(txn);
        var statusRecord = _statusStore.record(uid).cv()
          ..local.v = 1
          ..remote.v = 0
          ..deleted.v = 0
          ..path.v = path
          ..size.v = bytes.length
          ..accessed.v = _nextAccessed();
        await statusRecord.put(txn);
      },
    );

    return uid;
  }

  /// The local file of [fileId], it might not exist.
  Future<File> getMediaFile(String fileId) async {
    return (await _getMediaFile(fileId)).$2;
  }

  Future<(SdbSyncedMediaFile, File file)> _getMediaFile(String fileId) async {
    var fileRecord = await _mediaStore.record(fileId).get(database);
    var path = _ensurePath(fileId, fileRecord);
    return (fileRecord!, localFile(path));
  }

  /// Reads the local content of [fileId].
  ///
  /// Throws a [FileSystemException] when not present locally, see
  /// `SyncedMediaSdbSynchronizer.readMediaBytes` to read it from the source.
  Future<Uint8List> readMediaFileBytes(String fileId) async {
    return (await getMediaFile(fileId)).readAsBytes();
  }

  /// Checks if a media file exists locally and matches the recorded size.
  Future<bool> mediaFileExists(String fileId) async {
    var (mediaFile, file) = await _getMediaFile(fileId);
    var stat = await file.stat();
    return stat.size == mediaFile.size.v;
  }

  String _ensurePath(String fileId, SdbSyncedMediaFile? fileRecord) {
    if (fileRecord == null) {
      throw SyncedMediaSdbException(
        'Media file record not found for ID: $fileId',
      );
    }
    if (fileRecord.path.v == null) {
      throw SyncedMediaSdbException(
        'Media file path is missing for ID: $fileId',
      );
    }
    return fileRecord.path.v!;
  }

  /// Deletes the media file database entry [fileId], must be marked as deleted
  /// first.
  Future<void> purgeMediaFile(String fileId) async {
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var fileRecordRef = _mediaStore.record(fileId);
        final fileStatusRecordRef = _statusStore.record(fileId);
        var file = await fileRecordRef.get(txn);
        if (file != null && (file.deleted.v == true)) {
          await fileRecordRef.delete(txn);
          await fileStatusRecordRef.delete(txn);
        }
      },
    );
  }

  /// Mark the media as deleted and delete its local content, the content is
  /// deleted from the source on the next synchronization.
  ///
  /// [purge] deletes the records right away (no remote deletion).
  Future<void> deleteMediaFile(String fileId, {bool purge = false}) async {
    String? path;
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var fileRecordRef = _mediaStore.record(fileId);
        final fileStatusRecordRef = _statusStore.record(fileId);
        var file = await fileRecordRef.get(txn);
        var status =
            (await fileStatusRecordRef.get(txn)) ?? fileStatusRecordRef.cv();
        if (file != null) {
          path = file.path.v ?? status.path.v;
          if (purge) {
            await fileRecordRef.delete(txn);
            await fileStatusRecordRef.delete(txn);
          } else {
            file.deleted.v = true;
            status
              ..local.v = 0
              ..remote.v ??= file.isUploaded ? 1 : 0
              ..deleted.v = 1
              ..path.v ??= file.path.v;

            await file.put(txn);
            await status.put(txn);
          }
        }
      },
    );

    if (path != null) {
      await _deleteMediaFileBytes(path!);
    }
  }

  /// Gets all media file records from the database.
  Future<List<SdbSyncedMediaFile>> getAllRecords() async {
    return await _mediaStore.findRecords(database);
  }

  /// Media records as they change.
  Stream<List<SdbSyncedMediaFile>> onMediaFiles() =>
      _mediaStore.onRecords(database);

  /// Media record [fileId] as it changes.
  Stream<SdbSyncedMediaFile?> onMediaFile(String fileId) =>
      _mediaStore.record(fileId).onRecord(database);

  /// Media status [fileId] as it changes.
  Stream<SdbSyncedMediaFileStatus?> onMediaFileStatus(String fileId) =>
      _statusStore.record(fileId).onRecord(database);

  Future<List<String>> _statusIds(int local, int remote, int deleted) async {
    return await stores.statusIndex
        .record(local, remote, deleted)
        .findRecordPrimaryKeys(database);
  }

  /// File ids to upload: local only.
  Future<List<String>> fileIdsToUpload() => _statusIds(1, 0, 0);

  /// File ids to delete remotely: deleted, remote only.
  Future<List<String>> fileIdsToDeleteRemotely() => _statusIds(0, 1, 1);

  /// File ids to download: remote only.
  Future<List<String>> fileIdsToDownload() => _statusIds(0, 1, 0);

  /// File ids to delete locally: deleted remotely, local only.
  Future<List<String>> fileIdsToDeleteLocally() => _statusIds(1, 0, 1);

  /// File ids to purge: deleted, neither local nor remote.
  Future<List<String>> fileIdsToPurge() => _statusIds(0, 0, 1);

  /// File ids cached: local and remote, the ones that can be evicted.
  Future<List<String>> fileIdsCached() => _statusIds(1, 1, 0);

  /// File ids to inspect: no status info.
  Future<List<String>> fileIdsDirty() => _statusIds(0, 0, 0);

  /// Media record keys.
  Future<List<String>> findFileRecordKeys({SdbClient? client}) async {
    return await _mediaStore.findRecordKeys(client ?? database);
  }

  /// Status record keys.
  Future<List<String>> findFileStatusRecordKeys({SdbClient? client}) async {
    return await _statusStore.findRecordKeys(client ?? database);
  }

  /// Get media file record
  Future<SdbSyncedMediaFile?> getMediaFileRecord(String fileId) async {
    return await _mediaStore.record(fileId).get(database);
  }

  /// Get media file status
  Future<SdbSyncedMediaFileStatus?> getMediaFileStatus(String fileId) async {
    return await _statusStore.record(fileId).get(database);
  }

  /// All statuses with a local content.
  Future<List<SdbSyncedMediaFileStatus>> getLocalStatuses() async {
    var statuses = <SdbSyncedMediaFileStatus>[];
    for (var (remote, deleted) in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
      statuses.addAll(
        await stores.statusIndex
            .record(1, remote, deleted)
            .findObjects(database),
      );
    }
    return statuses;
  }

  /// Local cache stat (all local contents, uploaded or not).
  Future<SyncedMediaCacheStat> getCacheStat() async {
    var statuses = await getLocalStatuses();
    var size = 0;
    var pendingCount = 0;
    for (var status in statuses) {
      size += status.size.v ?? 0;
      if (!status.isRemote && !status.isDeleted) {
        pendingCount++;
      }
    }
    return SyncedMediaCacheStat(
      count: statuses.length,
      size: size,
      pendingCount: pendingCount,
    );
  }
}

/// Internal extension for [SyncedMediaSdb], for the synchronizer and tests.
extension SyncedMediaSdbInternalExt on SyncedMediaSdb {
  /// Update the status flags of [fileId].
  Future<void> updateStatus(
    String fileId, {
    bool? local,
    bool? remote,
    bool? localDeleted,
  }) async {
    await database.inScvStoresTransaction(
      [_statusStore],
      SdbTransactionMode.readWrite,
      (txn) async {
        var status =
            (await _statusStore.record(fileId).get(txn)) ??
            _statusStore.record(fileId).cv();

        local ??= status.isLocal;
        remote ??= status.isRemote;
        localDeleted ??= status.isDeleted;
        status
          ..setLocal(local)
          ..setDeleted(localDeleted)
          ..setRemote(remote);
        await status.put(txn);
      },
    );
  }

  /// Mark a file as present locally and remotely, and the record as uploaded
  /// (with its [url] if any).
  Future<void> markDownloadedAndUploaded(
    String fileId, {
    int? size,
    String? url,
  }) async {
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var file = await _mediaStore.record(fileId).get(txn);
        if (file != null) {
          if (!file.isUploaded || (url != null && file.url.v != url)) {
            file.uploaded.v = true;
            if (url != null) {
              file.url.v = url;
            }
            await file.put(txn);
          }
          var statusRef = _statusStore.record(fileId);
          var status = (await statusRef.get(txn)) ?? statusRef.cv();
          status
            ..setLocal(true)
            ..setRemote(true)
            ..setDeleted(false)
            ..path.v = file.path.v;
          if (size != null) {
            status.size.v = size;
          }
          status.accessed.v ??= 0;
          await status.put(txn);
        }
      },
    );
  }

  /// Mark a file as deleted locally
  Future<void> markLocalDeleted(String fileId) async {
    await _updateExistingStatus(fileId, (status) {
      status
        ..setLocal(false)
        ..setRemote(false)
        ..setDeleted(true);
    });
  }

  /// Mark a file as to upload
  Future<void> markToUpload(String fileId) async {
    await _updateExistingStatus(fileId, (status) {
      status
        ..setLocal(true)
        ..setRemote(false)
        ..setDeleted(false);
    });
  }

  /// Mark a file as remote deleted
  Future<void> markRemoteDeleted(String fileId) async {
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var file = await _mediaStore.record(fileId).get(txn);
        var statusRef = _statusStore.record(fileId);
        var fileStatus = (await statusRef.get(txn)) ?? statusRef.cv();
        if (file != null) {
          if (file.deleted.v != true) {
            file.deleted.v = true;
            await file.put(txn);
          }
          fileStatus
            ..setRemote(false)
            ..setDeleted(true);
          await fileStatus.put(txn);
        }
      },
    );
  }

  /// Mark a file as local not present
  @visibleForTesting
  Future<void> markLocalNotPresent(String fileId) async {
    await _updateExistingStatus(fileId, (status) {
      status.setLocal(false);
    });
  }

  /// Mark a file as no info, check on synchronization
  Future<void> markStatusCleared(String fileId) async {
    await _updateExistingStatus(fileId, (status) {
      status
        ..setLocal(false)
        ..setRemote(false)
        ..setDeleted(false);
    });
  }

  /// Delete the status of [fileId], rebuilt on synchronization.
  @visibleForTesting
  Future<void> deleteStatusRecord(String fileId) async {
    await _statusStore.record(fileId).delete(database);
  }

  /// Update the status of an existing media record.
  Future<void> _updateExistingStatus(
    String fileId,
    void Function(SdbSyncedMediaFileStatus status) update,
  ) async {
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var file = await _mediaStore.record(fileId).get(txn);
        if (file != null) {
          var statusRef = _statusStore.record(fileId);
          var status = (await statusRef.get(txn)) ?? statusRef.cv();
          update(status);
          await status.put(txn);
        }
      },
    );
  }

  /// Write the content of [file] read from the source, [accessed] now unless
  /// false (prefetch).
  Future<void> storeContent(
    SdbSyncedMediaFile file,
    Uint8List bytes, {
    bool accessed = true,
  }) async {
    var fileId = file.id;
    var path = file.path.v!;
    await _writeMediaFileBytes(path, bytes);
    var stored = false;
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        // Still there?
        var current = await _mediaStore.record(fileId).get(txn);
        if (current != null && !current.isDeleted) {
          var statusRef = _statusStore.record(fileId);
          var status = (await statusRef.get(txn)) ?? statusRef.cv();
          status
            ..setLocal(true)
            ..setRemote(true)
            ..setDeleted(false)
            ..path.v = path
            ..size.v = bytes.length
            ..accessed.v = accessed ? _nextAccessed() : 0;
          await status.put(txn);
          stored = true;
        }
      },
    );
    if (!stored) {
      await _deleteMediaFileBytes(path);
    }
  }

  /// Mark [fileId] as read now.
  Future<void> touch(String fileId) async {
    await database.inScvStoresTransaction(
      [_statusStore],
      SdbTransactionMode.readWrite,
      (txn) async {
        var status = await _statusStore.record(fileId).get(txn);
        if (status != null && status.isLocal) {
          status.accessed.v = _nextAccessed();
          await status.put(txn);
        }
      },
    );
  }

  /// Delete the local content of [fileId] if uploaded, it remains in the
  /// source.
  ///
  /// Returns true if evicted.
  Future<bool> evictContent(String fileId) async {
    String? path;
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var status = await _statusStore.record(fileId).get(txn);
        if (status != null && status.isLocal && status.isRemote) {
          path =
              status.path.v ??
              (await _mediaStore.record(fileId).get(txn))?.path.v;
          status
            ..setLocal(false)
            ..size.v = null
            ..accessed.v = null;
          await status.put(txn);
        }
      },
    );
    if (path != null) {
      await _deleteMediaFileBytes(path!);
      return true;
    }
    return false;
  }

  /// Delete the records and the local content of [fileId].
  Future<void> purge(String fileId) async {
    String? path;
    await database.inScvStoresTransaction(
      stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var fileRef = _mediaStore.record(fileId);
        var statusRef = _statusStore.record(fileId);
        var file = await fileRef.get(txn);
        var status = await statusRef.get(txn);
        path = file?.path.v ?? status?.path.v;
        await fileRef.delete(txn);
        await statusRef.delete(txn);
      },
    );
    if (path != null) {
      await _deleteMediaFileBytes(path!);
    }
  }

  /// Delete the local content at [path].
  Future<void> deleteContentAt(String path) => _deleteMediaFileBytes(path);
}
