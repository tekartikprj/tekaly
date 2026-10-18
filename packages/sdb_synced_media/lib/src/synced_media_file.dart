import 'package:path/path.dart';
import 'package:tekartik_app_media/mime_type.dart';
import 'package:tekartik_app_text/sanitize.dart';
import 'package:tekartik_common_utils/string_utils.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// True if [path] is a valid relative content path (no empty, `.` or `..`
/// segment, not absolute, no backslash).
bool syncedMediaIsValidPath(String path) {
  if (path.isEmpty || path.contains('\\') || url.isAbsolute(path)) {
    return false;
  }
  for (var segment in path.split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      return false;
    }
  }
  return true;
}

/// Reference to the content of a media file: its relative path, the same in
/// the local file system and in the remote source.
class SyncedMediaFileRef {
  /// Path (relative, url style).
  final String path;

  /// Reference from a relative [path].
  SyncedMediaFileRef.fromPath(this.path);

  @override
  int get hashCode => path.hashCode;

  @override
  bool operator ==(Object other) =>
      other is SyncedMediaFileRef && other.path == path;

  @override
  String toString() => path;
}

/// Media file info.
class SyncedMediaFile {
  /// New media file info for [filename], with a new unique id and its path
  /// (`ab/cd/ef/<uid>_<sanitized name>.<ext>`).
  factory SyncedMediaFile.from({
    required String filename,

    /// Type is guessed from filename if not provided
    String? type,

    /// Optional size
    int? size,
  }) {
    filename = buildOriginalFilename(filename);
    var uid = _uuid.v4().replaceAll('-', '');

    var folder1 = uid.substring(0, 2).toLowerCase();
    var folder2 = uid.substring(2, 4).toLowerCase();
    var folder3 = uid.substring(4, 6).toLowerCase();
    var fixedName = '${uid}_${_sanitizeAndTruncateOriginalFilename(filename)}';

    type ??= filenameMimeType(filename);
    var path = url.join(folder1, folder2, folder3, fixedName);
    return SyncedMediaFile(
      path: path,
      uid: uid,
      type: type,
      size: size,
      originalFilename: filename,
    );
  }

  /// Ref
  late final ref = SyncedMediaFileRef.fromPath(path);

  /// Build original file name from a full name or path, only take the base name
  static String buildOriginalFilename(String filename) {
    var originalFilename = filename.split('/').last.split('\\').last;
    if (originalFilename.isEmpty) {
      originalFilename = 'file';
    }
    return originalFilename;
  }

  static String _sanitizeAndTruncateOriginalFilename(String originalFilename) {
    var basename = sanitizeString(
      url.basenameWithoutExtension(originalFilename),
    ).truncate(24);
    var extension = _fileExtension(originalFilename);
    return '$basename.$extension';
  }

  /// no leading .
  static String _fileExtension(String filename) {
    var parts = filename.split('.');
    if (parts.length > 1) {
      return parts.last;
    } else {
      return '';
    }
  }

  /// Original filename
  final String originalFilename;

  /// Unique id, the record key.
  final String uid;

  /// Media type (mime type)
  final String type;

  /// Relative path of the content, locally and remotely.
  final String path;

  /// File size
  final int? size;

  /// Media file info.
  SyncedMediaFile({
    required this.uid,
    required this.originalFilename,
    required this.type,
    required this.path,
    required this.size,
  });

  @override
  String toString() => 'SyncedMediaFile($uid, $path, $type, $size)';
}
