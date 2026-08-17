import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:tekaly_file_picker/file_picker.dart';

/// [TekalyPickedFile] on top of a file_picker [fp.PlatformFile].
class TekalyPickedFilePlatformFile extends TekalyPickedFile {
  /// The wrapped file_picker file.
  final fp.PlatformFile platformFile;

  /// Wraps a file_picker file.
  TekalyPickedFilePlatformFile(this.platformFile);

  @override
  String get name => platformFile.name;

  @override
  Uri? get uri => platformFile.uri;

  @override
  String? get path => platformFile.path;

  @override
  Future<int> length() => platformFile.length();

  @override
  Future<Uint8List> readAsBytes() => platformFile.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => platformFile.readAsByteStream();

  @override
  String toString() => 'TekalyPickedFilePlatformFile($name)';
}

/// [TekalyPickedFile] on top of a file_selector/cross_file [XFile].
class TekalyPickedFileXFile extends TekalyPickedFile {
  /// The wrapped cross file.
  final XFile xFile;

  /// Wraps a cross file.
  TekalyPickedFileXFile(this.xFile);

  @override
  String get name => xFile.name;

  @override
  Uri? get uri {
    var path = xFile.path;
    return path.isEmpty ? null : Uri.file(path);
  }

  @override
  String? get path {
    var path = xFile.path;
    return path.isEmpty ? null : path;
  }

  @override
  Future<int> length() => xFile.length();

  @override
  Future<Uint8List> readAsBytes() => xFile.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => xFile.openRead();

  @override
  String toString() => 'TekalyPickedFileXFile($name)';
}
