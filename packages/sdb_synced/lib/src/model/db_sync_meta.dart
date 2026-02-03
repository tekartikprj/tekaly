// /syncedM/info
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

/// Sync meta info
class SdbSyncMetaInfo extends ScvStringRecordBase
    implements DbSyncMetaInfoCommon {
  /// source
  @override
  final source = CvField<String>('source');

  /// sourceVersion
  @override
  final sourceVersion = CvField<int>('sourceVersion');

  /// Source id if any TODO
  @override
  final sourceId = CvField<String>('sourceId');

  /// Last timestamp
  @override
  final lastTimestamp = cvEncodedTimestampField('lastTimestamp');

  /// Last change id, 0 if none after first sync
  @override
  final lastChangeId = CvField<int>('lastChangeId');

  @override
  List<CvField> get fields => [
    source,
    sourceId,
    lastTimestamp,
    lastChangeId,
    sourceVersion,
  ];
}
