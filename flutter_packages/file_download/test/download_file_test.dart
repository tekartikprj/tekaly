import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_file_download/download_file.dart';
import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';

void main() {
  group('DownloadFileInfo', () {
    test('mimeType', () {
      expect(
        DownloadFileInfo(
          filename: 'test.txt',
          data: utf8.encode('Hello World'),
        ).mimeType,
        'text/plain',
      );
      expect(filenameMimeType('test.png'), 'image/png');
    });
  });
  group('downloadFile', () {
    late TekalyFilePickerMemory filePicker;
    setUp(() {
      filePicker = TekalyFilePickerMemory(directoryPath: '/dir');
      tekalyFilePicker = filePicker;
    });
    test('saved using the file picker', () async {
      await downloadFile(
        DownloadFileInfo(
          filename: 'test.txt',
          data: utf8.encode('Hello World'),
        ),
      );
      var request = filePicker.saveRequests.single;
      expect(request.fileName, 'test.txt');
      expect(request.mimeType, 'text/plain');
      expect(utf8.decode(request.bytes), 'Hello World');
    });
    test('cancelled', () async {
      filePicker.cancelled = true;
      await downloadFile(
        DownloadFileInfo(filename: 'test.bin', data: utf8.encode('1')),
      );
      expect(filePicker.saveRequests.single.fileName, 'test.bin');
    });
  });
}
