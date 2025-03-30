import 'dart:typed_data';

import 'package:fs_shim/fs_shim.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_app_http/app_http.dart';
import 'package:tekartik_app_sembast/sembast.dart';
import 'package:path/path.dart';

import 'media_cache_db.dart';

abstract class TekalyMediaFetcher {
  Future<Uint8List> fetch(Uri uri);
}

class TekalyMediaFetcherDefault implements TekalyMediaFetcher {
  @override
  Future<Uint8List> fetch(Uri uri) async {
    var client = httpClientFactoryUniversal.newClient();
    try {
      return await httpClientReadBytes(client, httpMethodGet, uri);
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

  Stream<TekalyMediaContent> onMedia(TekalyMediaKey key);
  Future<TekalyMediaContent> cacheMedia(
    TekalyMediaKey key,
    Uri uri, {
    String? name,
    String? type,
  });

  /// The root directory of the cache
  Directory get rootDirectory;

  Future<void> clean();
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

  Context get p => rootDirectory.fs.path;

  @override
  Stream<TekalyMediaContent> onMedia(TekalyMediaKey key) async* {
    var db = await database;
    yield* dbMediaStore
        .record(key.id)
        .onRecord(db)
        .where((record) => record != null)
        .asyncMap((dbMedia) => _mediaContent(dbMedia!));
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

  Future<void> clear() async {
    var db = await database;
    await db.close();
    await rootDirectory.delete(recursive: true);
  }

  Future<TekalyMediaContent> _mediaContent(DbMedia dbMedia) async {
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
    return await _mediaContent(dbMedia);
  }

  @override
  Future<TekalyMediaContent> cacheMedia(
    TekalyMediaKey key,
    Uri uri, {
    String? name,
    String? type,
  }) async {
    try {
      var bytes = await mediaFetcher.fetch(uri);
      var size = bytes.lengthInBytes;
      var segments = uri.pathSegments;
      var filename =
          name ?? (segments.isNotEmpty ? url.basename(segments.last) : key.id);
      var db = await database;
      var file = mediaDirectory.file(filename);
      try {
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
      return TekalyMediaContent(info: record.mediaInfo, bytes: bytes);
    } catch (e) {
      print('error caching media $key: $e');
      rethrow;
    }
  }

  Future<void> _init() async {
    var dbName = 'tekaly_media_cache.db';
    var path = p.join(rootDirectory.path, 'tekaly_media_cache.db');
    print('open database $path');
    database = () async {
      return await databaseFactory.openDatabase(dbName);
    }();
    await database;
  }

  /// No longer usable
  Future<void> close() async {
    var db = await database;
    await db.close();
  }
}
