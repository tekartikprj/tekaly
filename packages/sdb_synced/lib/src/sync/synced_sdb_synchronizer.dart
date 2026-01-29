import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';

/// Synced db synchronized
class SyncedSdbSynchronizer extends SyncedDbSynchronizerCommon {
  SyncedSdbSynchronizer({
    required SyncedSdb db,
    required super.source,
    super.autoSync = false,
  }) : super(db: db);
}
