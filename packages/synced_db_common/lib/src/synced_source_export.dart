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

/// Name of the export file of [changeId]: `export_<changeId>.jsonl`, or
/// `export_v<sourceVersion>_<changeId>.jsonl` for a [sourceVersion] other than
/// null or 0 (the same for the synchronizers).
///
/// A file never changes once written: a new change id gives a new file, so it
/// can be cached forever. Change ids can start again with a new source
/// version, which is why the version is part of the name.
String syncedDbExportFileName(int changeId, {int? sourceVersion}) =>
    (sourceVersion ?? 0) == 0
    ? 'export_$changeId.jsonl'
    : 'export_v${sourceVersion}_$changeId.jsonl';

/// Name of the export meta file (`export_meta<suffix>.json`), the small file
/// pointing to the current export file.
String syncedDbExportMetaFileName({String? suffix}) =>
    'export_meta${suffix ?? ''}.json';

/// The change id and source version of an export file, see
/// [syncedDbExportFileName].
typedef SyncedDbExportFileId = ({int changeId, int? sourceVersion});

final _exportFileNameRegExp = RegExp(r'^export_(?:v(\d+)_)?(\d+)\.jsonl$');

/// The change id and source version of an export file name (see
/// [syncedDbExportFileName]), null for any other name.
SyncedDbExportFileId? syncedDbExportFileNameParse(String fileName) {
  var match = _exportFileNameRegExp.firstMatch(fileName);
  if (match == null) {
    return null;
  }
  var versionText = match.group(1);
  var sourceVersion = versionText == null ? null : int.tryParse(versionText);
  var changeId = int.tryParse(match.group(2)!);
  if (changeId == null || (versionText != null && sourceVersion == null)) {
    return null;
  }
  // Only the canonical name (no leading zero, no v0).
  if (syncedDbExportFileName(changeId, sourceVersion: sourceVersion) !=
      fileName) {
    return null;
  }
  return (changeId: changeId, sourceVersion: sourceVersion);
}
