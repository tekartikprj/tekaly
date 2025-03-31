import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_media_cache/src/media_cache_session.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_app_http/app_http.dart';
import 'package:tekartik_app_sembast/sembast.dart';
import 'package:path/path.dart';
// ignore: unused_import
import 'package:tekartik_common_utils/dev_utils.dart';
import 'media_cache_db.dart';

var debugTekalyMediaCache = false; // devWarning(true);
void _log(String message) {
  if (debugTekalyMediaCache) {
    print('/media_cache $message');
  }
}

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

extension TekalyMediaSourceInfoExt on TekalyMediaSourceInfo {
  String get nameValue => nonNullMediaName(name ?? mediaNameFromUri(uri));
}

/// Only in memory can be subclasses
abstract class TekalyMediaSourceInfo {
  TekalyMediaKey get key;
  Uri get uri;
  String? get name;
  String? get type;

  factory TekalyMediaSourceInfo(
    TekalyMediaKey key,
    Uri uri, {
    required String? name,
    required String? type,
  }) => _TekalyMediaSourceInfo(key: key, uri: uri, name: name, type: type);
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

abstract class TekalyMediaFetcher {
  Future<Uint8List> fetch(TekalyMediaSourceInfo uri);
}

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

class TekalyMediaInfo {
  final String name;
  final String? type;
  final int size;

  TekalyMediaInfo({required this.name, required this.type, required this.size});

  @override
  String toString() {
    return 'TekalyMediaInfo($name${type != null ? ', $type' : ''}, $size)';
  }
}

class TekalyMediaContent {
  final TekalyMediaInfo info;
  final Uint8List bytes;

  TekalyMediaContent({required this.info, required this.bytes});

  @override
  String toString() {
    return 'TekalyMediaContent: $info ${bytes.lengthInBytes}';
  }
}

abstract class TekalyMediaKey {
  String get id;
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

abstract class TekalyMediaCache {
  factory TekalyMediaCache({
    DatabaseFactory? databaseFactory,
    Directory? rootDirectory,
    TekalyMediaFetcher? mediaFetcher,
  }) {
    rootDirectory ??= fileSystemDefault.currentDirectory;
    databaseFactory =
        databaseFactory ?? getDatabaseFactory(rootPath: rootDirectory.path);
    return _TekalyMediaCache(
      rootDirectory: rootDirectory,
      databaseFactory: databaseFactory,
      mediaFetcher: mediaFetcher ?? TekalyMediaFetcherDefault(),
    );
  }

  Future<TekalyMediaContent?> getMedia(TekalyMediaKey key);
  Future<bool> isMediaCached(TekalyMediaKey key);

  Stream<TekalyMediaContent> onMedia(TekalyMediaKey key);
  Future<TekalyMediaContent> cacheMedia(TekalyMediaSourceInfo src);

  /// New session helper
  TekalyMediaCacheSession initSession();

  /// The root directory of the cache
  Directory get rootDirectory;

  /// To call regularly
  Future<void> clean();

  Future<void> clear();
}

class _TekalyMediaCache implements TekalyMediaCache {
  final DatabaseFactory databaseFactory;
  late Future<Database> database;
  final TekalyMediaFetcher mediaFetcher;
  @override
  final Directory rootDirectory;
  late final mediaDirectory = rootDirectory.directory('media');
  _TekalyMediaCache({
    required this.rootDirectory,
    required this.databaseFactory,
    required this.mediaFetcher,
  }) {
    cvAddConstructors([DbMedia.new]);
    _init();
  }

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
        .asyncMap((dbMedia) => _fileReadMediaContent(dbMedia!));
  }

  @override
  Future<void> clean() async {
    var db = await database;
    var foundFilenames = (await mediaDirectory.list().toList())
        .map((e) {
          return basename(e.path);
        })
        .nonNulls
        .where((path) => path.isNotEmpty);
    var filenames =
        (await dbMediaStore.find(db))
            .map((media) => media.name.v)
            .nonNulls
            .where((name) => name.isNotEmpty)
            .toSet();
    var toDelete = List.of(foundFilenames)
      ..removeWhere((name) => filenames.contains(name));

    for (var name in toDelete) {
      var file = mediaDirectory.file(name);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('error deleting $name: $e');
      }
    }
  }

  /// Close and delete the database
  /// Unsafe
  @override
  Future<void> clear() async {
    var db = await database;
    await dbMediaStore.delete(db);

    await rootDirectory.delete(recursive: true);
    await _init();
  }

  Future<TekalyMediaContent> _fileReadMediaContent(DbMedia dbMedia) async {
    var file = mediaDirectory.file(dbMedia.nameValue);
    var bytes = await file.readAsBytes();
    return TekalyMediaContent(info: dbMedia.mediaInfo, bytes: bytes);
  }

  @override
  Future<TekalyMediaContent?> getMedia(TekalyMediaKey key) async {
    var db = await database;
    var dbMedia = await dbMediaStore.record(key.id).get(db);
    if (dbMedia == null) {
      return null;
    }
    return await _fileReadMediaContent(dbMedia);
  }

  @override
  Future<bool> isMediaCached(TekalyMediaKey key) async {
    var db = await database;
    var dbMedia = await dbMediaStore.record(key.id).get(db);
    return (dbMedia?.cached.isNotNull ?? false);
  }

  @override
  Future<TekalyMediaContent> cacheMedia(TekalyMediaSourceInfo src) async {
    var key = src.key;
    try {
      if (debugTekalyMediaCache) {
        _log('cacheMedia $src');
      }
      var bytes = await mediaFetcher.fetch(src);
      var size = bytes.lengthInBytes;
      var filename = src.nameValue;
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
      record.type.setValue(src.type);
      record.size.value = size;
      record.cached.setValue(Timestamp.now());
      await dbMediaStore.record(key.id).put(db, record);
      return TekalyMediaContent(info: record.mediaInfo, bytes: bytes);
    } catch (e) {
      print('error caching media $src');
      rethrow;
    }
  }

  String get _dbPath {
    var dbName = 'tekaly_media_cache.db';
    var path = p.join(rootDirectory.path, dbName);
    return path;
  }

  Future<void> _init() async {
    print('open database $_dbPath');
    database = () async {
      return await databaseFactory.openDatabase(_dbPath);
    }();
    await database;
  }

  /// No longer usable
  Future<void> close() async {
    var db = await database;
    await db.close();
  }
}
