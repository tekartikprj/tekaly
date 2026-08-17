import 'dart:convert';
import 'dart:typed_data';

import 'file_picker.dart';
import 'file_type.dart';
import 'picked_file.dart';

/// In memory [TekalyPickedFile], its content is held as bytes.
class TekalyPickedFileMemory extends TekalyPickedFile {
  /// The whole content.
  final Uint8List bytes;

  @override
  final String name;

  @override
  final Uri? uri;

  /// Chunk size used by [readAsByteStream].
  final int chunkSize;

  /// Content held in memory.
  ///
  /// [uri] is optional, use `Uri.file(...)` to also get a [path].
  TekalyPickedFileMemory({
    required this.name,
    required List<int> bytes,
    this.uri,
    this.chunkSize = 64 * 1024,
  }) : bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  /// Content held in memory, from an utf-8 (by default) string.
  factory TekalyPickedFileMemory.fromString({
    required String name,
    required String text,
    Uri? uri,
    Encoding encoding = utf8,
  }) => TekalyPickedFileMemory(
    name: name,
    bytes: encoding.encode(text),
    uri: uri,
  );

  /// Content held in memory, located at [path], [name] defaults to the last
  /// path segment.
  factory TekalyPickedFileMemory.file({
    required String path,
    required List<int> bytes,
    String? name,
  }) {
    var uri = Uri.file(path);
    return TekalyPickedFileMemory(
      name: name ?? uri.pathSegments.last,
      bytes: bytes,
      uri: uri,
    );
  }

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      yield Uint8List.sublistView(
        bytes,
        offset,
        (offset + chunkSize).clamp(0, bytes.length),
      );
    }
  }

  @override
  String toString() => 'TekalyPickedFileMemory($name, ${bytes.length} bytes)';
}

/// A pick request recorded by [TekalyFilePickerMemory].
class TekalyFilePickRequest {
  /// Requested type.
  final TekalyPickFileType type;

  /// Requested extensions, when [type] is [TekalyPickFileType.custom].
  final List<String>? allowedExtensions;

  /// True for `pickFiles`, false for `pickFile`.
  final bool multiple;

  /// Requested dialog title.
  final String? dialogTitle;

  /// Requested initial directory.
  final String? initialDirectory;

  /// A recorded request.
  TekalyFilePickRequest({
    required this.type,
    this.allowedExtensions,
    this.multiple = false,
    this.dialogTitle,
    this.initialDirectory,
  });

  @override
  String toString() =>
      'TekalyFilePickRequest($type, multiple: $multiple, '
      'allowedExtensions: $allowedExtensions)';
}

/// A save request recorded by [TekalyFilePickerMemory].
class TekalyFileSaveRequest {
  /// Requested file name.
  final String fileName;

  /// The content to save.
  final Uint8List bytes;

  /// Requested mime type, `null` when not specified.
  final String? mimeType;

  /// Requested dialog title.
  final String? dialogTitle;

  /// Requested initial directory.
  final String? initialDirectory;

  /// A recorded request.
  TekalyFileSaveRequest({
    required this.fileName,
    required List<int> bytes,
    this.mimeType,
    this.dialogTitle,
    this.initialDirectory,
  }) : bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  @override
  String toString() =>
      'TekalyFileSaveRequest($fileName, ${bytes.length} bytes, $mimeType)';
}

/// In memory [TekalyFilePicker], for tests.
///
/// The files that the (simulated) user picks are the ones added to [files],
/// filtered by the requested type. Set [cancelled] to simulate a user
/// cancelling the dialog. Every request is recorded in [requests], every save
/// request in [saveRequests].
class TekalyFilePickerMemory implements TekalyFilePicker {
  /// The files available for picking, modifiable.
  final files = <TekalyPickedFile>[];

  /// The directory returned by [pickDirectoryPath] and where [saveFile]
  /// pretends to save.
  String? directoryPath;

  /// When true, every pick behaves as if the user cancelled the dialog.
  bool cancelled;

  /// All the requests received so far, in order.
  final requests = <TekalyFilePickRequest>[];

  /// All the save requests received so far, in order, with their content.
  final saveRequests = <TekalyFileSaveRequest>[];

  /// The uri returned by [saveFile], built from [directoryPath] when `null`.
  Uri? saveUri;

  /// In memory picker, optionally pre-filled with [files].
  TekalyFilePickerMemory({
    List<TekalyPickedFile>? files,
    this.directoryPath,
    this.cancelled = false,
  }) {
    if (files != null) {
      this.files.addAll(files);
    }
  }

  /// Add a file to [files] and return it.
  TekalyPickedFileMemory addFile({
    required String name,
    required List<int> bytes,
    Uri? uri,
  }) =>
      addPickedFile(TekalyPickedFileMemory(name: name, bytes: bytes, uri: uri));

  /// Add a text file to [files] and return it.
  TekalyPickedFileMemory addTextFile({
    required String name,
    required String text,
    Uri? uri,
  }) => addPickedFile(
    TekalyPickedFileMemory.fromString(name: name, text: text, uri: uri),
  );

  /// Add an existing picked file to [files] and return it.
  T addPickedFile<T extends TekalyPickedFile>(T file) {
    files.add(file);
    return file;
  }

  /// Remove all the files and the recorded requests.
  void clear() {
    files.clear();
    requests.clear();
    saveRequests.clear();
  }

  /// Whether [file] matches the requested [type]/[allowedExtensions].
  bool _matches(
    TekalyPickedFile file,
    TekalyPickFileType type,
    List<String>? allowedExtensions,
  ) {
    var extensions = tekalyPickFileTypeExtensions(type, allowedExtensions);
    return extensions == null || extensions.contains(file.extension);
  }

  List<TekalyPickedFile> _pick({
    required TekalyPickFileType type,
    required List<String>? allowedExtensions,
    required bool multiple,
    required String? dialogTitle,
    required String? initialDirectory,
  }) {
    checkTekalyPickFileArguments(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    requests.add(
      TekalyFilePickRequest(
        type: type,
        allowedExtensions: allowedExtensions,
        multiple: multiple,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      ),
    );
    if (cancelled) {
      return const [];
    }
    return files
        .where((file) => _matches(file, type, allowedExtensions))
        .toList();
  }

  @override
  Future<TekalyPickedFile?> pickFile({
    TekalyPickFileType type = TekalyPickFileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  }) async => _pick(
    type: type,
    allowedExtensions: allowedExtensions,
    multiple: false,
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  ).firstOrNull;

  @override
  Future<List<TekalyPickedFile>> pickFiles({
    TekalyPickFileType type = TekalyPickFileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
  }) async => _pick(
    type: type,
    allowedExtensions: allowedExtensions,
    multiple: true,
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );

  @override
  Future<String?> pickDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
  }) async => cancelled ? null : directoryPath;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    saveRequests.add(
      TekalyFileSaveRequest(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
      ),
    );
    if (cancelled) {
      return null;
    }
    return saveUri ?? _saveUri(fileName);
  }

  /// The default uri of a file saved as [fileName].
  Uri _saveUri(String fileName) {
    var directoryPath = this.directoryPath;
    return directoryPath == null
        ? Uri(path: fileName)
        : Uri.file('$directoryPath/$fileName', windows: false);
  }

  @override
  String toString() => 'TekalyFilePickerMemory(${files.length} file(s))';
}
