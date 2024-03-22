@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:tekaly_file_download_web/file_download.dart';

import 'package:test/test.dart';

import 'file_download_test.dart';

void main() {
  test('downloadFile', () async {
    var file = File(join('.local', 'download', 'test.txt'));
    await file.delete(recursive: true);
    expect(file.existsSync(), isFalse);
    await downloadFile(textFileInfo);
    expect(file.existsSync(), isTrue);
    expect(await file.readAsString(), 'Hello World');
  });
}
