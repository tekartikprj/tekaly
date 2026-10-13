import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fs_shim/fs_memory.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:tekaly_media_cache/media_cache.dart';
import 'package:tekaly_media_cache/src/media_cache.dart'
    show TekalyMediaCachePrvExt;
import 'package:test/test.dart';

/// Returns the uri as content.
class _Fetcher implements TekalyMediaFetcher {
  @override
  Future<Uint8List> fetch(TekalyMediaSourceInfo src) async =>
      utf8.encode('${src.uri}');
}

class _FailingDatabaseFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    int? version,
    OnVersionChangedFunction? onVersionChanged,
    DatabaseMode? mode,
    SembastCodec? codec,
  }) async {
    throw StateError('cannot open');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TekalyMediaCache _newCache({TekalyMediaCacheOptions? options}) {
  options ??= TekalyMediaCacheOptions();
  options.mediaFetcher = _Fetcher();
  return TekalyMediaCache(
    databaseFactory: newDatabaseFactoryMemory(),
    rootDirectory: newFileSystemMemory().directory('/root'),
    options: options,
  );
}

TekalyMediaSourceInfo _source(String key, String uri) =>
    TekalyMediaSourceInfo.parse(TekalyMediaKey.name(key), uri);

/// Run [action] in a zone recording the auto clean timers created.
Future<List<Timer>> _runRecordingTimers(Future<void> Function() action) async {
  var timers = <Timer>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        var timer = parent.createTimer(zone, duration, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
  return timers;
}

void main() {
  group('media_cache_memory', () {
    test('deleteOldMedias keeps the newest', () async {
      var cache = _newCache();
      for (var i = 0; i < 3; i++) {
        await cache.cacheMedia(_source('k$i', 'https://x/m$i.png'));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await cache.deleteOldMedias(keepCount: 2);
      expect((await cache.getAllMediaInfos()).map((info) => info.key.id), [
        'k1',
        'k2',
      ]);
      expect(await cache.getMedia(TekalyMediaKey.name('k0')), isNull);
      expect(
        utf8.decode((await cache.getMedia(TekalyMediaKey.name('k2')))!.bytes),
        'https://x/m2.png',
      );
      await cache.close();
    });

    test('keys of the same media name', () async {
      var cache = _newCache();
      var key1 = TekalyMediaKey.name('k1');
      var key2 = TekalyMediaKey.name('k2');
      await cache.cacheMedia(_source('k1', 'https://a.com/x/icon.png'));
      await cache.cacheMedia(_source('k2', 'https://b.com/y/icon.png'));
      var content1 = (await cache.getMedia(key1))!;
      expect(content1.info.name, 'icon.png');
      expect(utf8.decode(content1.bytes), 'https://a.com/x/icon.png');
      await cache.deleteMedia(key2);
      expect(
        utf8.decode((await cache.getMedia(key1))!.bytes),
        'https://a.com/x/icon.png',
      );
      // Media without a name in their uri
      await cache.cacheMedia(_source('t', 'https://www.tekartik.com'));
      await cache.cacheMedia(_source('g', 'https://www.google.com'));
      expect(
        utf8.decode((await cache.getMedia(TekalyMediaKey.name('t')))!.bytes),
        'https://www.tekartik.com',
      );
      // Nothing to clean
      await cache.clean();
      expect(await cache.getAllMediaInfos(), hasLength(3));
      await cache.close();
    });

    test('no auto clean timer after close', () async {
      var timers = await _runRecordingTimers(() async {
        var cache = _newCache(
          options: TekalyMediaCacheOptions(
            firstAutoCleanDuration: const Duration(minutes: 1),
            nextAutoCleanDuration: const Duration(minutes: 1),
          ),
        );
        await cache.database;
        // A clean in progress when closing
        var clean = cache.clean();
        await cache.close();
        await clean;
      });
      expect(timers, isNotEmpty);
      expect(timers.where((timer) => timer.isActive), isEmpty);
    });

    test('open failure', () async {
      var uncaughtErrors = <Object>[];
      await runZonedGuarded(() async {
        var cache = TekalyMediaCache(
          databaseFactory: _FailingDatabaseFactory(),
          rootDirectory: newFileSystemMemory().directory('/root'),
        );
        await expectLater(
          cache.getMediaInfo(TekalyMediaKey.name('k')),
          throwsStateError,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cache.close();
      }, (e, _) => uncaughtErrors.add(e));
      // Reported by the calls, never as an uncaught error
      expect(uncaughtErrors, isEmpty);
    });
  });
}
