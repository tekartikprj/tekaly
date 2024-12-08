// /syncedM/info
import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

/// Sync meta info
class DbSyncMetaInfo extends DbStringRecordBase {
  /// source
  final source = CvField<String>('source');

  /// sourceVersion
  final sourceVersion = CvField<int>('sourceVersion');

  /// Source id if any TODO
  final sourceId = CvField<String>('sourceId');

  /// Last timestamp
  final lastTimestamp = CvField<Timestamp>('lastTimestamp');

  /// Last change id, 0 if none after first sync
  final lastChangeId = CvField<int>('lastChangeId');

  @override
  List<CvField> get fields =>
      [source, sourceId, lastTimestamp, lastChangeId, sourceVersion];
}
