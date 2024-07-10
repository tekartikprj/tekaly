import 'package:cv/cv.dart';

/// Must be json encodable
class SyncedDbExportMeta extends CvModelBase {
  final lastChangeId = CvField<int>('lastChangeId');
  final lastTimestamp = CvField<String>('lastTimestamp');
  final sourceVersion = CvField<int>('sourceVersion');

  @override
  List<CvField> get fields => [lastChangeId, lastTimestamp, sourceVersion];
}

typedef SyncedDbSynchronizerFetchExportMeta = Future<Map<String, Object?>>
    Function();
typedef SyncedDbSynchronizerFetchExport = Future<String> Function(int changeId);
