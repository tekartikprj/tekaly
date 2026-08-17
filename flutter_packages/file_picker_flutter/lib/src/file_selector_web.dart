import 'dart:typed_data';

import 'package:tekaly_file_picker/file_picker.dart';

/// Never on the web, `file_picker` handles it.
bool get fileSelectorFallbackSupported => false;

/// Unsupported on the web.
Future<TekalyPickedFile?> fileSelectorPickFile({
  required TekalyPickFileType type,
  List<String>? allowedExtensions,
  String? dialogTitle,
  String? initialDirectory,
}) => throw UnsupportedError('file_selector fallback not supported on the web');

/// Unsupported on the web.
Future<List<TekalyPickedFile>> fileSelectorPickFiles({
  required TekalyPickFileType type,
  List<String>? allowedExtensions,
  String? dialogTitle,
  String? initialDirectory,
}) => throw UnsupportedError('file_selector fallback not supported on the web');

/// Unsupported on the web.
Future<String?> fileSelectorPickDirectoryPath({
  String? dialogTitle,
  String? initialDirectory,
}) => throw UnsupportedError('file_selector fallback not supported on the web');

/// Unsupported on the web.
Future<Uri?> fileSelectorSaveFile({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
  String? initialDirectory,
}) => throw UnsupportedError('file_selector fallback not supported on the web');
