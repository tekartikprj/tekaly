import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:tekaly_file_picker/file_picker.dart';

import 'picked_file_platform_file.dart';

/// True when the `file_selector` fallback is available and needed.
///
/// `file_picker` misbehaves on linux desktop, `file_selector` (gtk) is used
/// there instead.
bool get fileSelectorFallbackSupported => Platform.isLinux;

List<fs.XTypeGroup> _typeGroups(
  TekalyPickFileType type,
  List<String>? allowedExtensions,
) {
  var extensions = tekalyPickFileTypeExtensions(type, allowedExtensions);
  if (extensions == null || extensions.isEmpty) {
    return const [];
  }
  return [fs.XTypeGroup(label: type.name, extensions: extensions.toList())];
}

/// Pick a single file using `file_selector`, `null` when cancelled.
Future<TekalyPickedFile?> fileSelectorPickFile({
  required TekalyPickFileType type,
  List<String>? allowedExtensions,
  String? dialogTitle,
  String? initialDirectory,
}) async {
  var xFile = await fs.openFile(
    acceptedTypeGroups: _typeGroups(type, allowedExtensions),
    initialDirectory: initialDirectory,
    confirmButtonText: dialogTitle,
  );
  return xFile == null ? null : TekalyPickedFileXFile(xFile);
}

/// Pick multiple files using `file_selector`, empty when cancelled.
Future<List<TekalyPickedFile>> fileSelectorPickFiles({
  required TekalyPickFileType type,
  List<String>? allowedExtensions,
  String? dialogTitle,
  String? initialDirectory,
}) async {
  var xFiles = await fs.openFiles(
    acceptedTypeGroups: _typeGroups(type, allowedExtensions),
    initialDirectory: initialDirectory,
    confirmButtonText: dialogTitle,
  );
  return xFiles.map(TekalyPickedFileXFile.new).toList();
}

/// Pick a directory using `file_selector`, `null` when cancelled.
Future<String?> fileSelectorPickDirectoryPath({
  String? dialogTitle,
  String? initialDirectory,
}) => fs.getDirectoryPath(
  initialDirectory: initialDirectory,
  confirmButtonText: dialogTitle,
);

/// Save [bytes] using `file_selector`, `null` when cancelled.
///
/// `file_selector` only returns a location, the content is written here.
Future<Uri?> fileSelectorSaveFile({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
  String? initialDirectory,
}) async {
  var location = await fs.getSaveLocation(
    initialDirectory: initialDirectory,
    suggestedName: fileName,
    confirmButtonText: dialogTitle,
  );
  if (location == null) {
    return null;
  }
  var file = File(location.path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  return file.uri;
}
