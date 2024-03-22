import 'dart:convert';

import 'package:tekaly_file_download_web/file_download.dart';
import 'package:test/scaffolding.dart';

var textFileInfo =
    DownloadFileInfo(filename: 'test.txt', data: utf8.encode('Hello World'));
void main() {
  test('downloadFile', () async {
    await downloadFile(textFileInfo);
  });
}
