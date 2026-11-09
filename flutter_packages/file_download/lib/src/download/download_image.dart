import 'dart:typed_data';

import 'package:tekaly_file_download_web/file_download.dart'
    show DownloadFileInfo, filenameMimeType;

import 'download_file.dart';

/// An image to download with [downloadImage]: its name and its bytes.
///
/// The same as a [DownloadFileInfo] whose mime type comes from the extension
/// (see [DownloadImageInfoExtension.toDownloadFileInfo]).
class DownloadImageInfo {
  /// The file name, with its extension (`shot.png`): it gives the mime type.
  final String filename;

  /// The encoded image (png, jpeg, webp...).
  final Uint8List data;

  /// An image to download.
  DownloadImageInfo({required this.filename, required this.data});

  /// The mime type from the [filename] extension.
  String get mimeType => filenameMimeType(filename);

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
