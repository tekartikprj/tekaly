// ignore_for_file: directives_ordering

import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

import 'db_sync_record.dart';

export 'package:tekaly_sembast_synced/src/sync/model/source_record.dart';

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
  final syncTimestamp = cvEncodedTimestampField(syncTimestampKey);

  /// The record data
  @override
  final record = CvModelField<CvSyncedSourceRecordData>(recordFieldKey);
  //final store = CvField<String>(recordStoreFieldKey);
  //final key = CvField<String>(recordKeyFieldKey);
  //final deleted = CvField<bool>(recordDeletedFieldKey);
  //final value = CvField<Map>(recordValueFieldKey);

  @override
  List<CvField> get fields => [syncId, syncTimestamp, syncChangeId, record];
}
