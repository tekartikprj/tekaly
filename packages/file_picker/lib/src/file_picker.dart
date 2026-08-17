import 'dart:typed_data';

import 'picked_file.dart';

/// Default mime type used when saving a file of an unknown type.
const tekalyDefaultMimeType = 'application/octet-stream';

/// The type of file that can be picked.
enum TekalyPickFileType {
  /// Any file.
  any,

  /// Video and image files.
  media,

  /// Image files.
  image,

  /// Video files.
  video,

  /// Audio files.
  audio,

  /// Files matching the requested extensions.
  custom,
}

/// File picker interface.
///
/// The only entry point needed by an application, so that the actual
/// implementation (flutter, memory, ...) can be swapped at will.
abstract class TekalyFilePicker {
  /// Pick a single file, `null` when the user cancelled.
  ///
  /// [allowedExtensions] (lower case, without the leading dot) is required when
  /// [type] is [TekalyPickFileType.custom] and ignored otherwise.
  Future<TekalyPickedFile?> pickFile({
    TekalyPickFileType type = TekalyPickFileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  });

  /// Pick multiple files, empty when the user cancelled.
  ///
  /// See [pickFile] for the parameters.
  Future<List<TekalyPickedFile>> pickFiles({
    TekalyPickFileType type = TekalyPickFileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  });

  /// Pick a directory, `null` when the user cancelled.
  ///
  /// Not supported on all platforms (the web in particular), `null` is returned
  /// in this case.
  Future<String?> pickDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
  });

  /// Save [bytes] to a file chosen by the user, `null` when cancelled.
  ///
  /// [fileName] is the suggested name, extension included (`my_image.png`).
  /// [mimeType] defaults to [tekalyDefaultMimeType].
  ///
  /// The returned uri points to the saved file, its scheme depends on the
  /// platform (`file`, `content`, `blob`, ...) and it can be `null` even when
  /// the file was saved (the web in particular).
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    String? dialogTitle,
    String? initialDirectory,
  });
}

/// Common [TekalyFilePicker] helpers.
extension TekalyFilePickerExtension on TekalyFilePicker {
  /// Pick a single image file, `null` when the user cancelled.
  Future<TekalyPickedFile?> pickImageFile({
    String? dialogTitle,
    String? initialDirectory,
  }) => pickFile(
    type: TekalyPickFileType.image,
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );

  /// Pick a single file of any type, `null` when the user cancelled.
  Future<TekalyPickedFile?> pickAnyFile({
    String? dialogTitle,
    String? initialDirectory,
  }) => pickFile(dialogTitle: dialogTitle, initialDirectory: initialDirectory);

  /// Pick a single file matching [allowedExtensions] (lower case, without the
  /// leading dot), `null` when the user cancelled.
  Future<TekalyPickedFile?> pickCustomFile({
    required List<String> allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  }) => pickFile(
    type: TekalyPickFileType.custom,
    allowedExtensions: allowedExtensions,
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );
}

TekalyFilePicker? _tekalyFilePicker;

/// Global file picker.
///
/// Set it once at startup, `initTekalyFilePickerFlutter()` in
/// `tekaly_file_picker_flutter` or a `TekalyFilePickerMemory` in tests.
TekalyFilePicker get tekalyFilePicker =>
    _tekalyFilePicker ??
    (throw StateError(
      'tekalyFilePicker not initialized. Call initTekalyFilePickerFlutter() '
      '(package:tekaly_file_picker_flutter) or set a TekalyFilePickerMemory.',
    ));

/// Global file picker, `null` when not initialized yet.
///
/// For code that wants to use the global picker when there is one and fall back
/// to its own default otherwise.
TekalyFilePicker? get tekalyFilePickerOrNull => _tekalyFilePicker;

set tekalyFilePicker(TekalyFilePicker filePicker) =>
    _tekalyFilePicker = filePicker;

/// Check the arguments of a pick request, throws [ArgumentError] when invalid.
///
/// To be called by implementations.
void checkTekalyPickFileArguments({
  required TekalyPickFileType type,
  required List<String>? allowedExtensions,
}) {
  if (type == TekalyPickFileType.custom) {
    if (allowedExtensions == null || allowedExtensions.isEmpty) {
      throw ArgumentError.value(
        allowedExtensions,
        'allowedExtensions',
        'must not be empty when type is TekalyPickFileType.custom',
      );
    }
  }
}
