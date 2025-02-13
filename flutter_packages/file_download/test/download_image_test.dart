import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:tekaly_file_download/download_image.dart';

void main() {
  test('adds one to input values', () {
    var downloadImageInfo = DownloadImageInfo(
      filename: 'test.png',
      data: Uint8List.fromList([1, 2, 3]),
    );
    expect(
      downloadImageInfo.toString(),
      'DownloadImageInfo(test.png, 3 bytes, image/png)',
    );
  });
}
