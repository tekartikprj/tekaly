import 'dart:typed_data';

import 'package:tekaly_file_download_web/file_download.dart'
    show DownloadFileInfo;

import 'download_file.dart';

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

/// [DownloadImageInfo] as a [DownloadFileInfo].
extension DownloadImageInfoExtension on DownloadImageInfo {
  /// The matching file info, as used by `downloadFile`.
  DownloadFileInfo toDownloadFileInfo() =>
      DownloadFileInfo(filename: filename, data: data, mimeType: mimeType);
}

/// Download an image, see `downloadFile` for the generic helper.
Future<void> downloadImage(DownloadImageInfo imageInfo) =>
    downloadFile(imageInfo.toDownloadFileInfo());
