import 'dart:typed_data';

export 'download_image_io.dart'
    if (dart.library.js_interop) 'download_image_web.dart'; // ignore: uri_does_not_exist

class DownloadImageInfo {
  /// Must have the proper extension
  final String filename;
  final Uint8List data;

  DownloadImageInfo({required this.filename, required this.data});

  String get mimeType {
    if (filename.toLowerCase().endsWith('png')) {
      return 'image/png';
    } else {
      return 'image/jpg';
    }
  }

  @override
  String toString() =>
      'DownloadImageInfo($filename, ${data.length} bytes, $mimeType)';
}
