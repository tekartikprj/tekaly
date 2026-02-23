/// Check whether a store should be synced
/// by default store ending with _local are excluded
typedef SyncStorePredicate = bool Function(String store);

/// Synced db options
class SyncedDbOptions {
  /// Strict list of store names
  final List<String>? syncedStoreNames;

  /// Strict excluded list of store names
  final List<String>? syncedExcludedStoreNames;

  /// Dynamic predicate return true or false to allow syncing a store
  final SyncStorePredicate? predicate;

  SyncedDbOptions({
    this.syncedStoreNames,
    this.syncedExcludedStoreNames,
    this.predicate,
  });
}
