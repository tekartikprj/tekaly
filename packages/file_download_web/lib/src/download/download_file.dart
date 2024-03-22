import 'dart:typed_data';

import 'package:path/path.dart';

export 'download_file_stub.dart'
    if (dart.library.js_interop) 'download_file_web.dart'; // ignore: uri_does_not_exist

String filenameMimeType(String filename) {
  switch (extension(basename(filename.toLowerCase()))) {
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpg';
    case '.txt':
      return 'text/plain';
    case '.json':
      return 'application/json';
    case '.yaml':
      return 'application/yaml';
    case '.mp4':
      return 'video/mp4';
    default:
      return 'application/octet-stream';
  }
}

class DownloadFileInfo {
  /// Must have the proper extension
  final String filename;
  final Uint8List data;
  final String mimeType;

  DownloadFileInfo(
      {required this.filename, required this.data, String? mimeType})
      : mimeType = mimeType ?? filenameMimeType(filename);

  @override
  String toString() =>
      'DownloadImageInfo($filename, ${data.length} bytes, $mimeType)';
}
