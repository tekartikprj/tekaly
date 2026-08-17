import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:path/path.dart' as p;
import 'package:tekaly_file_picker/file_picker.dart';

import 'file_selector_io.dart'
    if (dart.library.js_interop) 'file_selector_web.dart';
import 'file_type.dart';
import 'picked_file_platform_file.dart';

/// Flutter [TekalyFilePicker], on top of `file_picker`.
///
/// On linux desktop, `file_selector` (gtk) is used instead as `file_picker`
/// misbehaves there, unless [useFileSelectorFallback] is false.
///
/// The directory of the last picked file is remembered in [lastDirectory] and
/// used as the initial directory of the next pick.
class TekalyFilePickerFlutter implements TekalyFilePicker {
  /// Use `file_selector` where `file_picker` misbehaves (linux desktop).
  final bool useFileSelectorFallback;

  /// Remember the directory of the last picked file and reuse it as the
  /// initial directory of the next pick.
  final bool rememberLastDirectory;

  /// The directory of the last picked file, `null` when unknown.
  String? lastDirectory;

  /// Flutter file picker.
  TekalyFilePickerFlutter({
    this.useFileSelectorFallback = true,
    this.rememberLastDirectory = true,
  });

  /// True when the `file_selector` fallback must be used.
  bool get _useFileSelector =>
      useFileSelectorFallback && fileSelectorFallbackSupported;

  String? _initialDirectory(String? initialDirectory) =>
      initialDirectory ?? (rememberLastDirectory ? lastDirectory : null);

  void _onPicked(List<TekalyPickedFile> files) {
    if (!rememberLastDirectory) {
      return;
    }
    var path = files.firstOrNull?.path;
    if (path != null) {
      lastDirectory = p.dirname(path);
    }
  }

  void _onSaved(Uri? uri) {
    if (!rememberLastDirectory) {
      return;
    }
    if (uri != null && uri.scheme == 'file') {
      lastDirectory = p.dirname(uri.toFilePath());
    }
  }

  @override
  Future<TekalyPickedFile?> pickFile({
    TekalyPickFileType type = TekalyPickFileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    checkTekalyPickFileArguments(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    initialDirectory = _initialDirectory(initialDirectory);
    TekalyPickedFile? file;
    if (_useFileSelector) {
      file = await fileSelectorPickFile(
        type: type,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
    } else {
      var platformFile = await fp.FilePicker.pickFile(
        type: toFilePickerFileType(type),
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      file = platformFile == null
          ? null
          : TekalyPickedFilePlatformFile(platformFile);
    }
    _onPicked([?file]);
    return file;
  }

  @override
  Future<List<TekalyPickedFile>> pickFiles({
    TekalyPickFileType type = TekalyPickFileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    checkTekalyPickFileArguments(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    initialDirectory = _initialDirectory(initialDirectory);
    List<TekalyPickedFile> files;
    if (_useFileSelector) {
      files = await fileSelectorPickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
    } else {
      var platformFiles = await fp.FilePicker.pickFiles(
        type: toFilePickerFileType(type),
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      );
      files = platformFiles.map(TekalyPickedFilePlatformFile.new).toList();
    }
    _onPicked(files);
    return files;
  }

  @override
  Future<String?> pickDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    initialDirectory = _initialDirectory(initialDirectory);
    var path = _useFileSelector
        ? await fileSelectorPickDirectoryPath(
            dialogTitle: dialogTitle,
            initialDirectory: initialDirectory,
          )
        : await fp.FilePicker.getDirectoryPath(
            dialogTitle: dialogTitle,
            initialDirectory: initialDirectory,
          );
    if (path != null && rememberLastDirectory) {
      lastDirectory = path;
    }
    return path;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    initialDirectory = _initialDirectory(initialDirectory);
    var uri = _useFileSelector
        ? await fileSelectorSaveFile(
            fileName: fileName,
            bytes: bytes,
            dialogTitle: dialogTitle,
            initialDirectory: initialDirectory,
          )
        : await fp.FilePicker.saveFile(
            fileName: fileName,
            bytes: bytes,
            mimeType: mimeType ?? tekalyDefaultMimeType,
            dialogTitle: dialogTitle,
            initialDirectory: initialDirectory,
          );
    _onSaved(uri);
    return uri;
  }

  @override
  String toString() => 'TekalyFilePickerFlutter()';
}

TekalyFilePickerFlutter? _tekalyFilePickerFlutter;

/// The default flutter file picker, created on first access.
TekalyFilePickerFlutter get tekalyFilePickerFlutter =>
    _tekalyFilePickerFlutter ??= TekalyFilePickerFlutter();

/// Set the global `tekalyFilePicker` (from `tekaly_file_picker`) to the flutter
/// implementation.
///
/// To be called once at startup, before any pick. [filePicker] can be specified
/// to customize the implementation.
TekalyFilePicker initTekalyFilePickerFlutter({
  TekalyFilePickerFlutter? filePicker,
}) {
  if (filePicker != null) {
    _tekalyFilePickerFlutter = filePicker;
  }
  return tekalyFilePicker = tekalyFilePickerFlutter;
}
