import 'dart:async';
import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

import 'synced_media_cache_options.dart';
import 'synced_media_file.dart';
import 'synced_media_sdb.dart';
import 'synced_media_source.dart';

/// Debug flag for media synchronization.
var debugSyncedMedia = false; // devWarning(true);

void _log(Object? message) {
  // ignore: avoid_print
  print('[synced_media] $message');
}

/// Synchronizes the contents of a [SyncedMediaSdb] with a [SyncedMediaSource]
/// and reads them through the local cache ([cacheOptions]).
///
/// The media records themselves are synchronized with the database holding
/// them (a `SyncedSdb`), see [startAutoSync].
class SyncedMediaSdbSynchronizer {
  /// The local db
  final SyncedMediaSdb db;

  /// The source
  final SyncedMediaSource source;

  /// Local cache options.
  final SyncedMediaCacheOptions cacheOptions;

  /// Store the source network url in the media record on upload, so that
  /// every client gets it without asking the source (it is then readable by
  /// anyone reading the record).
  final bool storeUrl;

  final _lock = Lock(reentrant: true);
  final _trimLock = Lock();
  final _downloads = <String, Future<Uint8List>>{};
  final _urls = <String, Uri?>{};
  StreamSubscription<Object?>? _autoSyncSubscription;
  var _closed = false;

  /// Synchronizes [db] with [source].
  SyncedMediaSdbSynchronizer({
    required this.db,
    required this.source,
    this.cacheOptions = const SyncedMediaCacheOptions.all(),
    this.storeUrl = false,
  });

  SyncedMediaSdbStores get _stores => db.stores;

  bool get _isLru => cacheOptions.mode == SyncedMediaCacheMode.lru;

  /// Fixes the statuses from the media records: new records (from the
  /// source), records deleted by another client (local content deleted),
  /// records purged by another client (orphan statuses), lost statuses.
  Future<SyncedSyncStat> reconcile() async {
    late List<SdbSyncedMediaFile> records;
    late List<SdbSyncedMediaFileStatus> statuses;
    await db.database.inScvStoresTransaction(
      _stores.stores,
      SdbTransactionMode.readOnly,
      (txn) async {
        records = await _stores.mediaStore.findRecords(txn);
        statuses = await _stores.statusStore.findRecords(txn);
      },
    );
    var recordMap = {for (var record in records) record.id: record};
    var statusMap = {for (var status in statuses) status.id: status};

    var ids = <String>{};
    for (var status in statuses) {
      if (!recordMap.containsKey(status.id)) {
        ids.add(status.id);
      }
    }
    for (var record in records) {
      var status = statusMap[record.id];
      if (status == null ||
          status.path.v == null ||
          (record.isDeleted && !status.isDeleted) ||
          (!record.isDeleted &&
              !status.isDeleted &&
              !status.isLocal &&
              !status.isRemote &&
              record.isUploaded)) {
        ids.add(record.id);
      }
    }

    var stat = SyncedSyncStat();
    for (var id in ids) {
      if (_closed) {
        break;
      }
      stat.add(await _reconcileOne(id));
    }
    return stat;
  }

  Future<SyncedSyncStat> _reconcileOne(String fileId) async {
    String? deleteLocalPath;
    String? deleteRemotePath;
    String? checkPendingPath;
    await db.database.inScvStoresTransaction(
      _stores.stores,
      SdbTransactionMode.readWrite,
      (txn) async {
        var record = await _stores.mediaStore.record(fileId).get(txn);
        var statusRef = _stores.statusStore.record(fileId);
        var status = await statusRef.get(txn);
        if (record == null) {
          // Purged (by another client)
          if (status != null) {
            if (debugSyncedMedia) {
              _log('orphan status $status');
            }
            var path = status.path.v;
            if (path != null) {
              if (status.isLocal) {
                deleteLocalPath = path;
              }
              if (status.isRemote && status.isDeleted) {
                deleteRemotePath = path;
              }
            }
            await statusRef.delete(txn);
          }
          return;
        }
        var path = record.path.v;
        if (status == null) {
          // New from the source or lost
          if (debugSyncedMedia) {
            _log('new status for $record');
          }
          status = statusRef.cv()
            ..setLocal(false)
            ..setRemote(record.isUploaded)
            ..setDeleted(record.isDeleted)
            ..path.v = path;
          await status.put(txn);
          if (!record.isUploaded && !record.isDeleted) {
            checkPendingPath = path;
          }
          return;
        }
        var changed = false;
        if (status.path.v == null && path != null) {
          status.path.v = path;
          changed = true;
        }
        if (record.isDeleted) {
          if (!status.isDeleted) {
            // Deleted by another client
            if (status.isLocal) {
              deleteLocalPath = status.path.v;
            }
            status
              ..setLocal(false)
              ..setRemote(status.isRemote || record.isUploaded)
              ..setDeleted(true)
              ..size.v = null
              ..accessed.v = null;
            changed = true;
          }
        } else if (!status.isDeleted &&
            !status.isLocal &&
            !status.isRemote &&
            record.isUploaded) {
          // Uploaded by another client
          status.setRemote(true);
          changed = true;
        }
        if (changed) {
          await status.put(txn);
        }
      },
    );
    var stat = SyncedSyncStat();
    if (deleteLocalPath != null) {
      await db.deleteContentAt(deleteLocalPath!);
      stat.localDeletedCount++;
    }
    if (deleteRemotePath != null && syncedMediaIsValidPath(deleteRemotePath!)) {
      await source.deleteMediaFile(
        SyncedMediaFileRef.fromPath(deleteRemotePath!),
      );
      stat.remoteDeletedCount++;
    }
    if (checkPendingPath != null) {
      // Lost status of a content not uploaded yet, still there?
      var file = db.localFile(checkPendingPath!);
      if (await file.exists()) {
        await db.updateStatus(fileId, local: true);
      }
    }
    return stat;
  }

  /// Uploads the local contents, deletes the deleted ones from the source.
  Future<SyncedSyncStat> syncUp() async {
    var remoteCreated = 0;
    for (var fileId in await db.fileIdsToUpload()) {
      if (_closed) {
        break;
      }
      var fileRecord = await db.getMediaFileRecord(fileId);
      if (fileRecord != null) {
        try {
          var bytes = await db.readMediaFileBytes(fileId);
          await source.addMediaFile(
            file: fileRecord.toMediaFile(),
            bytes: bytes,
          );
          String? url;
          if (storeUrl) {
            try {
              url = (await source.getMediaUrl(fileRecord.fileRef))?.toString();
            } catch (e) {
              _log('no url for $fileId: $e');
            }
          }
          await db.markDownloadedAndUploaded(
            fileId,
            size: bytes.length,
            url: url,
          );
          remoteCreated++;
        } on FileSystemException catch (e, st) {
          _log('ignoring error $e');
          if (debugSyncedMedia) {
            _log(st);
          }
          // Not found locally, re-download
          if (fileRecord.isUploaded && !fileRecord.isDeleted) {
            await db.updateStatus(fileId, local: false, remote: true);
          }
        }
      }
    }
    var remoteDeleted = 0;
    for (var fileId in await db.fileIdsToDeleteRemotely()) {
      if (_closed) {
        break;
      }
      if (await _deleteRemote(fileId)) {
        remoteDeleted++;
      }
      await db.purge(fileId);
    }
    // Deleted before being uploaded (or its upload not known yet)
    for (var fileId in await db.fileIdsToPurge()) {
      if (_closed) {
        break;
      }
      var fileRecord = await db.getMediaFileRecord(fileId);
      if (fileRecord?.isUploaded ?? false) {
        if (await _deleteRemote(fileId)) {
          remoteDeleted++;
        }
      }
      await db.purge(fileId);
    }
    return SyncedSyncStat(
      remoteCreatedCount: remoteCreated,
      remoteDeletedCount: remoteDeleted,
    );
  }

  Future<bool> _deleteRemote(String fileId) async {
    var path =
        (await db.getMediaFileRecord(fileId))?.path.v ??
        (await db.getMediaFileStatus(fileId))?.path.v;
    if (path == null || !syncedMediaIsValidPath(path)) {
      return false;
    }
    await source.deleteMediaFile(SyncedMediaFileRef.fromPath(path));
    return true;
  }

  /// Deletes the contents deleted remotely, downloads the remote contents
  /// ([SyncedMediaCacheMode.all], or [SyncedMediaCacheOptions.prefetch]).
  Future<SyncedSyncStat> syncDown() async {
    var localDeleted = 0;
    for (var fileId in await db.fileIdsToDeleteLocally()) {
      if (_closed) {
        break;
      }
      await db.purge(fileId);
      localDeleted++;
    }

    var localCreated = 0;
    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> download(SdbSyncedMediaFile record) async {
      var path = record.path.v;
      if (path == null || !syncedMediaIsValidPath(path)) {
        _log('skipping ${record.id} invalid path $path');
        return;
      }
      try {
        await _download(record);
        localCreated++;
      } catch (e, st) {
        _log('download ${record.id} failed: $e');
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }

    switch (cacheOptions.mode) {
      case SyncedMediaCacheMode.all:
        for (var fileId in await db.fileIdsToDownload()) {
          if (_closed) {
            break;
          }
          var record = await db.getMediaFileRecord(fileId);
          if (record != null) {
            await download(record);
          }
        }
      case SyncedMediaCacheMode.lru:
        if (cacheOptions.prefetch) {
          var records = <SdbSyncedMediaFile>[];
          for (var fileId in await db.fileIdsToDownload()) {
            var record = await db.getMediaFileRecord(fileId);
            if (record != null) {
              records.add(record);
            }
          }
          // Newest first
          records.sort(
            (a, b) =>
                _compareTimestamp(b.createdTimestamp.v, a.createdTimestamp.v),
          );
          var cacheStat = await db.getCacheStat();
          var count = cacheStat.count;
          var size = cacheStat.size;
          var maxCount = cacheOptions.maxCount;
          var maxSize = cacheOptions.maxSize;
          for (var record in records) {
            if (_closed || (maxCount != null && count >= maxCount)) {
              break;
            }
            var recordSize = record.size.v;
            if (maxSize != null &&
                (recordSize == null || size + recordSize > maxSize)) {
              continue;
            }
            await download(record);
            count++;
            size += recordSize ?? 0;
          }
        }
      case SyncedMediaCacheMode.none:
        break;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
    return SyncedSyncStat(
      localCreatedCount: localCreated,
      localDeletedCount: localDeleted,
    );
  }

  static int _compareTimestamp(SdbTimestamp? a, SdbTimestamp? b) {
    if (a == null) {
      return b == null ? 0 : -1;
    } else if (b == null) {
      return 1;
    }
    return a.compareTo(b);
  }

  /// Synchronizes the contents (reconcile, up, down) then trims the cache.
  Future<SyncedSyncStat> sync() async {
    if (_closed) {
      return SyncedSyncStat(notExecuted: true);
    }
    return await _lock.synchronized(() async {
      if (_closed) {
        return SyncedSyncStat(notExecuted: true);
      }
      var stat = await reconcile();
      stat.add(await syncUp());
      try {
        stat.add(await syncDown());
      } finally {
        await trimCache();
      }
      if (debugSyncedMedia) {
        _log('sync: $stat');
      }
      return stat;
    });
  }

  var _lazySyncRequested = false;
  Future<void>? _lazySyncFuture;

  /// Synchronizes, coalescing the calls made while a synchronization runs
  /// into one more. Never throws, errors are logged.
  Future<void> lazySync() {
    _lazySyncRequested = true;
    return _lazySyncFuture ??= () async {
      try {
        while (_lazySyncRequested && !_closed) {
          _lazySyncRequested = false;
          try {
            await sync();
          } catch (e) {
            _log('sync failed: $e');
          }
        }
      } finally {
        _lazySyncFuture = null;
      }
    }();
  }

  /// Synchronizes now and on each [onSynced] event, typically
  /// `SyncedSdbSynchronizer.onSynced()` of the database holding the media
  /// records (new, deleted media records from other clients, local media to
  /// upload once their record is pushed).
  void startAutoSync(Stream<Object?> onSynced) {
    _autoSyncSubscription?.cancel().ignore();
    _autoSyncSubscription = onSynced.listen((_) {
      lazySync().ignore();
    });
    lazySync().ignore();
  }

  /// Evicts the least recently read contents above the limits
  /// ([SyncedMediaCacheMode.lru]), every uploaded content
  /// ([SyncedMediaCacheMode.none]).
  ///
  /// Returns the number of contents evicted.
  Future<int> trimCache() async {
    if (cacheOptions.mode == SyncedMediaCacheMode.all) {
      return 0;
    }
    return await _trimLock.synchronized(() async {
      var statuses = await db.getLocalStatuses();
      var count = statuses.length;
      var size = 0;
      for (var status in statuses) {
        size += status.size.v ?? 0;
      }
      var maxCount = cacheOptions.maxCount;
      var maxSize = cacheOptions.maxSize;
      bool overLimits() =>
          cacheOptions.mode == SyncedMediaCacheMode.none ||
          (maxCount != null && count > maxCount) ||
          (maxSize != null && size > maxSize);
      if (!overLimits()) {
        return 0;
      }
      // Uploaded only, least recently read first
      var evictable =
          statuses
              .where((status) => status.isRemote && !status.isDeleted)
              .toList()
            ..sort((a, b) {
              var cmp = (a.accessed.v ?? 0).compareTo(b.accessed.v ?? 0);
              if (cmp == 0) {
                cmp = a.id.compareTo(b.id);
              }
              return cmp;
            });
      var evicted = 0;
      for (var status in evictable) {
        if (!overLimits()) {
          break;
        }
        if (await db.evictContent(status.id)) {
          if (debugSyncedMedia) {
            _log('evicted $status');
          }
          evicted++;
          count--;
          size -= status.size.v ?? 0;
        }
      }
      return evicted;
    });
  }

  /// Reads the content from the source, kept locally if the cache keeps it.
  Future<Uint8List> _download(SdbSyncedMediaFile record) {
    var fileId = record.id;
    var pending = _downloads[fileId];
    if (pending != null) {
      return pending;
    }
    var future = () async {
      var bytes = await source.readMediaFileBytes(record.fileRef);
      if (cacheOptions.keepRead) {
        await db.storeContent(record, bytes, accessed: false);
      }
      return bytes;
    }();
    _downloads[fileId] = future;
    future.whenComplete(() => _downloads.remove(fileId)).ignore();
    return future;
  }

  Future<SdbSyncedMediaFile> _getExistingRecord(String fileId) async {
    var record = await db.getMediaFileRecord(fileId);
    if (record == null || record.isDeleted) {
      throw SyncedMediaSdbException('Media file not found for ID: $fileId');
    }
    return record;
  }

  /// Reads the content of [fileId], locally if present, from the source
  /// otherwise (kept locally unless [SyncedMediaCacheMode.none]).
  Future<Uint8List> readMediaBytes(String fileId) async {
    var record = await _getExistingRecord(fileId);
    var status = await db.getMediaFileStatus(fileId);
    if (status?.isLocal ?? false) {
      try {
        var bytes = await db.readMediaFileBytes(fileId);
        if (_isLru) {
          await db.touch(fileId);
        }
        return bytes;
      } on FileSystemException catch (_) {
        // Lost (or evicted meanwhile), read it from the source if uploaded
        if (!record.isUploaded) {
          rethrow;
        }
        if (debugSyncedMedia) {
          _log('local content of $fileId lost');
        }
        await db.updateStatus(fileId, local: false, remote: true);
      }
    }
    var bytes = await _download(record);
    if (_isLru) {
      await db.touch(fileId);
      await trimCache();
    }
    return bytes;
  }

  /// The local file of [fileId] if present (marked as read), null otherwise.
  Future<File?> getCachedMediaFile(String fileId) async {
    var status = await db.getMediaFileStatus(fileId);
    if (status?.isLocal ?? false) {
      var file = await db.getMediaFile(fileId);
      if (await file.exists()) {
        if (_isLru) {
          await db.touch(fileId);
        }
        return file;
      }
    }
    return null;
  }

  /// The network url of the content of [fileId]: stored in the record (see
  /// [storeUrl]) or given by the source (kept in memory), null if not
  /// uploaded yet or if the source has none.
  Future<Uri?> getMediaUrl(String fileId) async {
    var record = await _getExistingRecord(fileId);
    var url = record.url.v;
    if (url != null) {
      return Uri.parse(url);
    }
    if (!record.isUploaded) {
      return null;
    }
    if (_urls.containsKey(fileId)) {
      return _urls[fileId];
    }
    var uri = await source.getMediaUrl(record.fileRef);
    _urls[fileId] = uri;
    return uri;
  }

  /// Local cache stat.
  Future<SyncedMediaCacheStat> getCacheStat() => db.getCacheStat();

  /// Stops the auto sync, waits for the current synchronization.
  Future<void> close() async {
    _closed = true;
    await _autoSyncSubscription?.cancel();
    _autoSyncSubscription = null;
    try {
      await _lazySyncFuture;
    } catch (_) {}
    await _lock.synchronized(() {});
  }
}
