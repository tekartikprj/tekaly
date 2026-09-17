// ignore_for_file: directives_ordering

import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

export 'package:tekaly_synced_db_common/synced_db_common.dart'
    show
        SyncedSourceRecordData,
        SyncedRecordKey,
        CvSyncedSourceRecordData,
        SyncedSourceRecordMixin,
        CvSyncedSourceRecordExt,
        SyncedSourceRecord,
        CvSyncedSourceRecordCoreMeta,
        CvSyncedSourceRecord;

/// Mixin
mixin SdbSyncedSourceRecordMixin implements CvSyncedSourceRecord {
  /// Sync id if any, this is the firestore hence not save in firestore
  @override
  final syncId = CvField<String>(syncIdKey);

  /// Server change id
  @override
  final syncChangeId = CvField<int>(syncChangeIdKey);

  /// Server timestamp
  @override
  final syncTimestamp = CvField<SdbTimestamp>(syncTimestampKey);

  /// The record data
  @override
  final record = CvModelField<CvSyncedSourceRecordData>(recordFieldKey);

  @override
  List<CvField> get fields => [syncId, syncTimestamp, syncChangeId, record];
}
