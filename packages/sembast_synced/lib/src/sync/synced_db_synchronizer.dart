import 'synced_db.dart';

/// Sync either from an export or from firestore
abstract class SyncedDbDownSynchronizer {
  SyncedDb get db;

  /// synchronized (down)
  Future<void> sync();
}

mixin SyncedDbDownSynchronizerMixin implements SyncedDbDownSynchronizer {
  @override
  late SyncedDb db;
}
