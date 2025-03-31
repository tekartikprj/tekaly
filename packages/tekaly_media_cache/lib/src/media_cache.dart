import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:path/path.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_media_cache/src/media_cache_session.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_app_http/app_http.dart';
import 'package:tekartik_app_sembast/sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
// ignore: unused_import
import 'package:tekartik_common_utils/dev_utils.dart';

import 'media_cache_db.dart';

/// Internal extra logs
var debugTekalyMediaCache = false; // devWarning(true);

void _log(String message) {
  if (debugTekalyMediaCache) {
    // ignore: avoid_print
    print('/media_cache $message');
  }
}

/// Media name from uri
String? mediaNameFromUri(Uri uri) {
  var segments = uri.pathSegments;
  if (segments.isNotEmpty) {
    return segments.last;
  }
  return null;
}

/// Never null
String nonNullMediaName(String? name) {
  if (name == null || name.isEmpty) {
    return 'media_default';
  }
  return name;
}

/// Media source info extension
extension TekalyMediaSourceInfoExt on TekalyMediaSourceInfo {
  /// Get the media local name
  String get nameValue => nonNullMediaName(name ?? mediaNameFromUri(uri));
  TekalyMediaInfo _mediaInfo({required int size}) {
    return TekalyMediaInfo(key: key, name: nameValue, type: type, size: size);
  }

  /// build a media content
  TekalyMediaContent mediaContent({required Uint8List bytes}) {
    return TekalyMediaContent(
      info: _mediaInfo(size: bytes.length),
      bytes: bytes,
    );
  }
}

/// Only in memory can be subclasses
abstract class TekalyMediaSourceInfo {
  /// The media key
  TekalyMediaKey get key;

  /// The media uri
  Uri get uri;

  /// The media name (local)
  String? get name;

  /// The media type (mime type)
  String? get type;

  /// Factory to create a media source info
  factory TekalyMediaSourceInfo(
    TekalyMediaKey key,
    Uri uri, {
    required String? name,
    required String? type,
  }) => _TekalyMediaSourceInfo(key: key, uri: uri, name: name, type: type);

  /// Uri parser helper
  factory TekalyMediaSourceInfo.parse(
    TekalyMediaKey key,
    String uri, {
    String? name,
    String? type,
  }) {
    return TekalyMediaSourceInfo(key, Uri.parse(uri), name: name, type: type);
  }
}

class _TekalyMediaSourceInfo implements TekalyMediaSourceInfo {
  @override
  final TekalyMediaKey key;
  @override
  final Uri uri;
  @override
  final String? type;
  @override
  final String? name;
  _TekalyMediaSourceInfo({
    required this.key,
    required this.uri,
    required this.name,
    required this.type,
  });

  @override
  String toString() {
    return 'Source($key, $nameValue, $type, $uri)';
  }
}

/// Media fetcher
abstract class TekalyMediaFetcher {
  /// Fetch the media
  Future<Uint8List> fetch(TekalyMediaSourceInfo uri);
}

/// Default media fetcher
class TekalyMediaFetcherDefault implements TekalyMediaFetcher {
  @override
  Future<Uint8List> fetch(TekalyMediaSourceInfo uri) async {
    var client = httpClientFactoryUniversal.newClient();
    try {
      return await httpClientReadBytes(client, httpMethodGet, uri.uri);
    } finally {
      client.close();
    }
  }
}

/// Media info
class TekalyMediaInfo {
  /// The media key
  final TekalyMediaKey key;

  /// The media name
  final String name;

  /// Mime type
  final String? type;

  /// The media size
  final int size;

  /// The media info
  TekalyMediaInfo({
    required this.key,
    required this.name,
    required this.type,
    required this.size,
  });

  @override
  String toString() {
    return 'TekalyMediaInfo($key, $name${type != null ? ', $type' : ''}, $size)';
  }
}

/// Media content
class TekalyMediaContent {
  /// The media info
  final TekalyMediaInfo info;

  /// The media key
  TekalyMediaKey get key => info.key;

  /// The media bytes
  final Uint8List bytes;

  /// Media content
  TekalyMediaContent({required this.info, required this.bytes});

  @override
  String toString() {
    return 'TekalyMediaContent: $info ${bytes.length}';
  }
}

/// Media key
abstract class TekalyMediaKey {
  /// The media key id
  String get id;

  /// The media key name
  factory TekalyMediaKey.name(String name) {
    return _TekalyMediaKeyName(name);
  }
}

class _TekalyMediaKeyName implements TekalyMediaKey {
  @override
  String get id => name;
  final String name;
  _TekalyMediaKeyName(this.name);
  @override
  String toString() => 'Key($name)';

  @override
  int get hashCode => name.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is _TekalyMediaKeyName) {
      return other.name == name;
    }
    return false;
  }
}

/// Media cache options
class TekalyMediaCacheOptions {
  /// The media fetcher
  TekalyMediaFetcher? mediaFetcher;

  /// The first auto clean duration
  Duration? firstAutoCleanDuration;

  /// The next auto clean duration
  Duration? nextAutoCleanDuration;

  /// Media cache options
  TekalyMediaCacheOptions({
    this.mediaFetcher,
    this.firstAutoCleanDuration,
    this.nextAutoCleanDuration,
  });
}

/// Media cache
abstract class TekalyMediaCache {
  /// Create a new media cache
  factory TekalyMediaCache({
    DatabaseFactory? databaseFactory,
    Directory? rootDirectory,
    TekalyMediaCacheOptions? options,
  }) {
    rootDirectory ??= fileSystemDefault.currentDirectory;
    databaseFactory =
        databaseFactory ?? getDatabaseFactory(rootPath: rootDirectory.path);
    return _TekalyMediaCache(
      options: options ?? TekalyMediaCacheOptions(),
      rootDirectory: rootDirectory,
      databaseFactory: databaseFactory,
      mediaFetcher: options?.mediaFetcher ?? TekalyMediaFetcherDefault(),
    );
  }

  /// Get the media content
  Future<TekalyMediaContent?> getMedia(TekalyMediaKey key);

  /// Check if the media is cached
  Future<bool> isMediaCached(TekalyMediaKey key);

  /// get the media content by stream
  Stream<TekalyMediaContent> onMedia(TekalyMediaKey key);

  /// Fetch the media (not cached)
  Future<TekalyMediaContent> fetchMedia(TekalyMediaSourceInfo src);

  /// Cache the media
  Future<TekalyMediaContent> cacheMedia(TekalyMediaSourceInfo src);

  /// New session helper
  TekalyMediaCacheSession initSession();

  /// The root directory of the cache contains db and media dir
  Directory get rootDirectory;

  /// The media directory of the cache
  Directory get mediaDirectory;

  /// Internal use
  Future<Database> get database;

  /// To call regularly, call automatically otherwise
  Future<void> clean();

  /// Clear the cache, file system and database
  Future<void> clear();

  /// Dump the database
  Future dump();

  /// Close the database
  Future<void> close();

  /// Cache a given content
  Future<void> cacheContent(TekalyMediaContent content);
}

class _TekalyMediaCache implements TekalyMediaCache {
  final TekalyMediaCacheOptions options;
  final DatabaseFactory databaseFactory;
  @override
  late Future<Database> database;
  final TekalyMediaFetcher mediaFetcher;
  Timer? autoCleanTimer;
  @override
  final Directory rootDirectory;
  @override
  late final mediaDirectory = rootDirectory.directory('media');
  _TekalyMediaCache({
    required this.options,
    required this.rootDirectory,
    required this.databaseFactory,
    required this.mediaFetcher,
  }) {
    cvAddConstructors([DbMedia.new]);
    _init();
  }

  final _lock = Lock();

  @override
  TekalyMediaCacheSession initSession() => TekalyMediaCacheSession(this);

  Context get p => rootDirectory.fs.path;

  @override
  Stream<TekalyMediaContent> onMedia(TekalyMediaKey key) async* {
    var db = await database;
    yield* dbMediaStore
        .record(key.id)
        .onRecord(db)
        .where((record) => record != null)
        .asyncMap((dbMedia) => _fileReadMediaContent(key, dbMedia!));
  }

  @override
  Future<void> clean() async {
    await _lock.synchronized(() async {
      cleanCount++;

      /// Find files without dbEntry
      /// and dbEntry without files
      try {
        var db = await database;
        var foundFilenames =
            (await mediaDirectory.exists())
                ? (await mediaDirectory.list().toList())
                    .map((e) {
                      return basename(e.path);
                    })
                    .nonNulls
                    .where((path) => path.isNotEmpty)
                : <String>[];
        var filenames =
            (await dbMediaStore.find(db))
                .map((media) => media.name.v)
                .nonNulls
                .where((name) => name.isNotEmpty)
                .toSet();
        var toDelete = List.of(foundFilenames)
          ..removeWhere((name) => filenames.contains(name));

        var dbToDelete = List.of(filenames)
          ..removeWhere((name) => foundFilenames.contains(name));
        if (dbToDelete.isNotEmpty) {
          await dbMediaStore.delete(
            db,
            finder: Finder(
              filter: Filter.inList(dbMediaModel.name.key, dbToDelete),
            ),
          );
        }
        for (var name in toDelete) {
          var file = mediaDirectory.file(name);
          try {
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            if (debugTekalyMediaCache) {
              _log('error deleting file $file: $e');
            }
          }
        }
      } finally {
        scheduleAutoClean();
      }
    });
  }

  var _clearingOrClosing = false;

  /// Close and delete the database
  /// Unsafe
  @override
  Future<void> clear() async {
    await _lock.synchronized(() async {
      if (_clearingOrClosing) {
        return;
      }
      try {
        _clearingOrClosing = true;
        autoCleanTimer?.cancel();
        var db = await database;
        await db.dropAll();
        await mediaDirectory.delete(recursive: true);
      } finally {
        _clearingOrClosing = false;
      }
    });
  }

  Future<TekalyMediaContent> _fileReadMediaContent(
    TekalyMediaKey key,
    DbMedia dbMedia,
  ) async {
    var file = mediaDirectory.file(dbMedia.nameValue);
    var bytes = await file.readAsBytes();
    return TekalyMediaContent(info: dbMedia.mediaInfo(key: key), bytes: bytes);
  }

  @override
  Future<TekalyMediaContent?> getMedia(TekalyMediaKey key) async {
    var db = await database;
    var dbMedia = await dbMediaStore.record(key.id).get(db);
    if (dbMedia == null) {
      return null;
    }
    try {
      return await _fileReadMediaContent(key, dbMedia);
    } catch (e) {
      // file not found, clean it
      await dbMediaStore.record(key.id).delete(db);
      return null;
    }
  }

  @override
  Future<bool> isMediaCached(TekalyMediaKey key) async {
    var db = await database;
    var dbMedia = await dbMediaStore.record(key.id).get(db);
    return (dbMedia?.cached.isNotNull ?? false);
  }

  @override
  Future<TekalyMediaContent> cacheContent(TekalyMediaContent content) async {
    return await _lock.synchronized(() async {
      var info = content.info;
      var key = content.key;
      var filename = info.name;
      var type = info.type;
      try {
        if (debugTekalyMediaCache) {
          _log('cacheContent $content');
        }
        assert(content.bytes.length == info.size);
        var bytes = content.bytes;
        var size = bytes.length;
        var db = await database;
        var file = mediaDirectory.file(filename);
        try {
          _log('writing file $file');
          await file.writeAsBytes(bytes);
        } catch (_) {
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        }
        var record = DbMedia();
        record.name.value = filename;
        record.type.setValue(type);
        record.size.value = size;
        record.cached.setValue(Timestamp.now());
        await dbMediaStore.record(key.id).put(db, record);
        return TekalyMediaContent(
          info: record.mediaInfo(key: key),
          bytes: bytes,
        );
      } catch (e) {
        if (debugTekalyMediaCache) {
          _log('error caching media $content: $e');
        }
        rethrow;
      }
    });
  }

  @override
  Future<TekalyMediaContent> cacheMedia(TekalyMediaSourceInfo src) async {
    try {
      if (debugTekalyMediaCache) {
        _log('cacheMedia $src');
      }

      var bytes = await mediaFetcher.fetch(src);
      return await cacheContent(src.mediaContent(bytes: bytes));
    } catch (e) {
      if (debugTekalyMediaCache) {
        _log('cacheMedia error $src: $e');
      }

      rethrow;
    }
  }

  @override
  Future<TekalyMediaContent> fetchMedia(TekalyMediaSourceInfo src) async {
    try {
      if (debugTekalyMediaCache) {
        _log('fetchMedia $src');
      }

      var bytes = await mediaFetcher.fetch(src);
      return src.mediaContent(bytes: bytes);
    } catch (e) {
      if (debugTekalyMediaCache) {
        _log('fetchMedia error $src: $e');
      }
      rethrow;
    }
  }

  String get _dbPath {
    var dbName = 'tekaly_media_cache.db';
    var path = p.join(rootDirectory.path, dbName);
    return path;
  }

  Future<void> _init() async {
    // print('open database $_dbPath');
    database = () async {
      return await databaseFactory.openDatabase(_dbPath);
    }();
    await database.then((_) {
      scheduleAutoClean();
    });
  }

  var firstAutoCleanDone = false;
  static const _firstAutoCleanDuration = Duration(seconds: 5);
  static const _autoCleanDuration = Duration(seconds: 15);

  void scheduleAutoClean() {
    var duration =
        firstAutoCleanDone
            ? (options.nextAutoCleanDuration ?? _autoCleanDuration)
            : (options.firstAutoCleanDuration ?? _firstAutoCleanDuration);
    autoCleanTimer?.cancel();
    firstAutoCleanDone = true;

    autoCleanTimer = Timer(duration, () async {
      await clean();
    });
  }

  /// No longer usable
  @override
  Future<void> close() async {
    autoCleanTimer?.cancel();
    var db = await database;
    await db.close();
  }

  @override
  Future dump() async {
    var db = await database;
    var records = await dbMediaStore.find(db);
    for (var record in records) {
      // ignore: avoid_print
      print('record: $record');
    }
  }

  var cleanCount = 0;
}

/// TekalyMediaCache extension
extension TekalyMediaCachePrvExt on TekalyMediaCache {
  _TekalyMediaCache get _self => this as _TekalyMediaCache;

  /// Internal use
  int get cleanCount => _self.cleanCount;
}
