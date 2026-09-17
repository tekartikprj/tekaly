// /syncedM/info
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

export 'package:tekaly_synced_db_common/synced_db_common.dart'
    show DbSyncMetaInfoCommon;

/// Sync meta info
class DbSyncMetaInfo extends DbStringRecordBase
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
  final lastTimestamp = CvField<SyncedDbTimestamp>('lastTimestamp');

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
