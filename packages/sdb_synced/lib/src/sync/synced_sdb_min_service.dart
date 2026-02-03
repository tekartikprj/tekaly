//import 'package:tekaly_sembast_synced/src/sync/synced_source.dart';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/sdb_synced.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';

export 'package:tekaly_sdb_synced/synced_sdb_internals.dart' show SyncedSource;

/// Min service for reading a record from a synced database (local or remote)
abstract class SyncedSdbReadMinService {
  /// Implementation of the synced database service
  ///
  factory SyncedSdbReadMinService.syncedDb({required SyncedSdb syncedDb}) {
    return _SyncedDbLocalMinService(syncedDb: syncedDb);
  }

  Future<Model?> getRecordData(SyncedSdbRecordRef ref);

  /// Remote
  factory SyncedSdbReadMinService.syncedSource({
    required SyncedSource syncedSource,
  }) {
    return _SyncedDbSyncedSourceMinService(syncedSource: syncedSource);
  }
}

class _SyncedDbLocalMinService implements SyncedSdbReadMinService {
  _SyncedDbLocalMinService({required this.syncedDb});

  final SyncedSdb syncedDb;

  @override
  Future<Model?> getRecordData(SyncedSdbRecordRef ref) async {
    return (await ref.getValue(await syncedDb.database));
  }
}

class _SyncedDbSyncedSourceMinService implements SyncedSdbReadMinService {
  _SyncedDbSyncedSourceMinService({required this.syncedSource});

  final SyncedSource syncedSource;

  @override
  Future<Model?> getRecordData(SyncedSdbRecordRef ref) async {
    var sourceRecord = await syncedSource.getSourceRecord(
      SyncedDataSourceRef(
        key: ref.key,
        store: ref.store.name,
      ).fixedSourceSyncId(),
    );
    return sourceRecord?.record.v?.value.v;
  }
}
