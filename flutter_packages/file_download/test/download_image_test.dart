import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_file_download/download_image.dart';
import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';

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
  test('mimeType', () {
    String mimeType(String filename) =>
        DownloadImageInfo(filename: filename, data: Uint8List(0)).mimeType;
    expect(mimeType('test.png'), 'image/png');
    expect(mimeType('test.PNG'), 'image/png');
    expect(mimeType('test.jpg'), 'image/jpeg');
    expect(mimeType('test.jpeg'), 'image/jpeg');
    expect(mimeType('test.webp'), 'image/webp');
    expect(mimeType('test.gif'), 'image/gif');
  });
  test('downloadImage', () async {
    var filePicker = TekalyFilePickerMemory();
    tekalyFilePicker = filePicker;
    await downloadImage(
      DownloadImageInfo(
        filename: 'test.png',
        data: Uint8List.fromList([1, 2, 3]),
      ),
    );
    var request = filePicker.saveRequests.single;
    expect(request.fileName, 'test.png');
    expect(request.mimeType, 'image/png');
    expect(request.bytes, [1, 2, 3]);
  });
}
