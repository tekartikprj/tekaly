import 'package:tekaly_media_cache/src/media_cache.dart';

void _log(String message) {
  if (debugTekalyMediaCache) {
    print('/media_cache_session $message');
  }
}

abstract class TekalyMediaCacheSession {
  /// Cache the last icon urls
  void addSource(TekalyMediaSourceInfo item);
  TekalyMediaSourceInfo? getSource(TekalyMediaKey key);

  factory TekalyMediaCacheSession(TekalyMediaCache cache) =>
      _TekalyMediaCacheSession(cache: cache);
  Iterable<TekalyMediaKey> getAllKeys();
}

class _TekalyMediaCacheSession implements TekalyMediaCacheSession {
  final TekalyMediaCache cache;

  _TekalyMediaCacheSession({required this.cache});
  final _map = <TekalyMediaKey, TekalyMediaSourceInfo>{};
  @override
  TekalyMediaSourceInfo? getSource(TekalyMediaKey key) {
    return _map[key];
  }

  @override
  Iterable<TekalyMediaKey> getAllKeys() => _map.keys;
  @override
  void addSource(TekalyMediaSourceInfo item) {
    if (debugTekalyMediaCache) {
      _log('addUri $item');
    }
    _map[item.key] = item;
  }
}
