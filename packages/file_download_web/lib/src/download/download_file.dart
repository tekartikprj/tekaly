import 'dart:typed_data';

import 'package:tekaly_file_download_web/src/mime_type.dart';

export 'download_file_stub.dart'
    if (dart.library.js_interop) 'download_file_web.dart'; // ignore: uri_does_not_exist

class DownloadFileInfo {
  /// Must have the proper extension
  final String filename;
  final Uint8List data;
  final String mimeType;

  DownloadFileInfo({
    required this.filename,
    required this.data,
    String? mimeType,
  }) : mimeType = mimeType ?? filenameMimeType(filename);

  @override
  String toString() =>
      'DownloadImageInfo($filename, ${data.length} bytes, $mimeType)';
}
