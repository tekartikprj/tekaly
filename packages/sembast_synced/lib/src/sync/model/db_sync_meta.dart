// /syncedM/info
import 'package:sembast/timestamp.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

class DbSyncMetaInfo extends DbStringRecordBase {
  /// TODO
  final source = CvField<String>('source');
  final sourceVersion = CvField<int>('sourceVersion');

  /// Source id if any TODO
  final sourceId = CvField<String>('sourceId');

  final lastTimestamp = CvField<Timestamp>('lastTimestamp');
  final lastChangeId = CvField<int>('lastChangeId');

  @override
  List<CvField> get fields =>
      [source, sourceId, lastTimestamp, lastChangeId, sourceVersion];
}
