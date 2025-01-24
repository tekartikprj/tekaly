import 'package:cv/cv.dart';

/// Must be json encodable
class SyncedDbExportMeta extends CvModelBase {
  /// Last change id
  final lastChangeId = CvField<int>('lastChangeId');

  /// Last sync timestamp
  final lastTimestamp = CvField<String>('lastTimestamp');

  /// Source version
  final sourceVersion = CvField<int>('sourceVersion');

  @override
  List<CvField> get fields => [lastChangeId, lastTimestamp, sourceVersion];
}

/// Must be json encodable
typedef SyncedDbSynchronizerFetchExportMeta = Future<Map<String, Object?>>
    Function();

/// String but typically jsonl
typedef SyncedDbSynchronizerFetchExport = Future<String> Function(int changeId);
