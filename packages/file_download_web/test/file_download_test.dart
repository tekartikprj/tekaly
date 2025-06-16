import 'dart:convert';

import 'package:tekaly_file_download_web/file_download.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

var textFileInfo = DownloadFileInfo(
  filename: 'test.txt',
  data: utf8.encode('Hello World'),
);
var textFileInfo2 = DownloadFileInfo(
  filename: 'test2.txt',
  data: utf8.encode('Hello World'),
);
void main() {
  test('downloadFile', () async {
    await downloadFile(textFileInfo2);
  });
  test('mimeType', () {
    expect(filenameMimeType('test.txt'), 'text/plain');
    expect(filenameMimeType('test2.gif'), 'image/gif');
  });
}
