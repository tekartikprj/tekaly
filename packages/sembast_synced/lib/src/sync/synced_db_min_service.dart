import 'package:tekaly_sembast_synced/src/sync/synced_source.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

import '../../synced_db.dart';

/// Min service for reading a record from a synced database (local or remote)
abstract class SyncedDbReadMinService {
  /// Implementation of the synced database service
  ///
  factory SyncedDbReadMinService.syncedDb({required SyncedDb syncedDb}) {
    return _SyncedDbLocalMinService(syncedDb: syncedDb);
  }
  Future<Model?> getRecordData(SyncedDbRecordRef ref);

  /// Remote
  factory SyncedDbReadMinService.syncedSource({
    required SyncedSource syncedSource,
  }) {
    return _SyncedDbSyncedSourceMinService(syncedSource: syncedSource);
  }
}

class _SyncedDbLocalMinService implements SyncedDbReadMinService {
  _SyncedDbLocalMinService({required this.syncedDb});

  final SyncedDb syncedDb;
  @override
  Future<Model?> getRecordData(SyncedDbRecordRef ref) async {
    return await ref.get(await syncedDb.database);
  }
}

class _SyncedDbSyncedSourceMinService implements SyncedDbReadMinService {
  _SyncedDbSyncedSourceMinService({required this.syncedSource});

  final SyncedSource syncedSource;
  @override
  Future<Model?> getRecordData(SyncedDbRecordRef ref) async {
    var sourceRecord = await syncedSource.getSourceRecord(
      SyncedDataSourceRef(
        key: ref.key,
        store: ref.store.name,
      ).fixedSourceSyncId(),
    );
    return sourceRecord?.record.v?.value.v;
  }
}
