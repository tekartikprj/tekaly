import 'dart:convert';
import 'dart:typed_data';

/// A file picked by a picker.
///
/// Deliberately free of any `dart:io`, web or flutter dependency so that it can
/// be implemented on top of any picker (native, web, memory) and easily mocked.
abstract class TekalyPickedFile {
  /// The name of the file, including its extension (`my_image.png`).
  String get name;

  /// An uri to the underlying file, `null` when unknown.
  ///
  /// Depending on the implementation, it can point to a local file, a blob, a
  /// data uri or a network resource.
  Uri? get uri;

  /// The local file path, `null` when the file is not on the local disk.
  String? get path {
    var uri = this.uri;
    return (uri != null && uri.scheme == 'file') ? uri.toFilePath() : null;
  }

  /// The length of the file in bytes.
  Future<int> length();

  /// Read the whole content at once.
  ///
  /// Prefer [readAsByteStream] for big files.
  Future<Uint8List> readAsBytes();

  /// Read the content as a stream of chunks.
  Stream<Uint8List> readAsByteStream();
}

/// Common [TekalyPickedFile] helpers.
extension TekalyPickedFileExtension on TekalyPickedFile {
  /// Lower case extension without the leading dot, empty when there is none.
  String get extension {
    var index = name.lastIndexOf('.');
    if (index < 0 || index == name.length - 1) {
      return '';
    }
    return name.substring(index + 1).toLowerCase();
  }

  /// Read the whole content as a string, utf-8 by default.
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());
}
