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
typedef SyncedDbSynchronizerFetchExportMeta =
    Future<Map<String, Object?>> Function();

/// String but typically jsonl
typedef SyncedDbSynchronizerFetchExport = Future<String> Function(int changeId);

/// Name of the export file of [changeId] (`export_<changeId>.jsonl`).
///
/// A file never changes once written: a new change id gives a new file, so it
/// can be cached forever.
String syncedDbExportFileName(int changeId) => 'export_$changeId.jsonl';

/// Name of the export meta file (`export_meta<suffix>.json`), the small file
/// pointing to the current export file.
String syncedDbExportMetaFileName({String? suffix}) =>
    'export_meta${suffix ?? ''}.json';
