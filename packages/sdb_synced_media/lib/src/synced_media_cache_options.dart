/// How the contents of the remote media are kept locally.
enum SyncedMediaCacheMode {
  /// Every content is downloaded on synchronization and kept (offline first).
  all,

  /// Contents are downloaded when read (and optionally prefetched), the least
  /// recently read ones are evicted above the limits.
  lru,

  /// No content is kept locally once uploaded, it is read from the source
  /// each time (or displayed from its network url).
  none,
}

/// Local cache options of the media contents.
///
/// Contents added locally and not uploaded yet are always kept, whatever the
/// mode and limits (they count in the limits but are never evicted).
class SyncedMediaCacheOptions {
  /// Mode
  final SyncedMediaCacheMode mode;

  /// Maximum number of contents kept ([SyncedMediaCacheMode.lru] only), no
  /// limit if null.
  final int? maxCount;

  /// Maximum total size in bytes of the contents kept
  /// ([SyncedMediaCacheMode.lru] only), no limit if null.
  final int? maxSize;

  /// Download remote contents on synchronization, newest first, as long as
  /// they fit in the limits without evicting anything
  /// ([SyncedMediaCacheMode.lru] only, always true for
  /// [SyncedMediaCacheMode.all]).
  final bool prefetch;

  /// Keep every content locally, downloaded on synchronization (default).
  const SyncedMediaCacheOptions.all()
    : mode = SyncedMediaCacheMode.all,
      maxCount = null,
      maxSize = null,
      prefetch = true;

  /// Keep the most recently read contents, up to [maxCount] contents and
  /// [maxSize] bytes.
  ///
  /// Without limits, it is a download on demand cache never evicting
  /// anything.
  const SyncedMediaCacheOptions.lru({
    this.maxCount,
    this.maxSize,
    this.prefetch = false,
  }) : mode = SyncedMediaCacheMode.lru;

  /// Keep no remote content locally.
  const SyncedMediaCacheOptions.none()
    : mode = SyncedMediaCacheMode.none,
      maxCount = null,
      maxSize = null,
      prefetch = false;

  /// True if a content read from the source is kept locally.
  bool get keepRead => mode != SyncedMediaCacheMode.none;

  @override
  String toString() => switch (mode) {
    SyncedMediaCacheMode.all => 'SyncedMediaCacheOptions.all()',
    SyncedMediaCacheMode.none => 'SyncedMediaCacheOptions.none()',
    SyncedMediaCacheMode.lru =>
      'SyncedMediaCacheOptions.lru(maxCount: $maxCount, maxSize: $maxSize'
          '${prefetch ? ', prefetch' : ''})',
  };
}
