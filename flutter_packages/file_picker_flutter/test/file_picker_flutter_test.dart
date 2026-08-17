import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

void main() {
  group('TekalyFilePickerFlutter', () {
    test('is a TekalyFilePicker', () {
      expect(TekalyFilePickerFlutter(), isA<TekalyFilePicker>());
      expect(tekalyFilePickerFlutter, isA<TekalyFilePickerFlutter>());
    });
    test('initTekalyFilePickerFlutter', () {
      var filePicker = TekalyFilePickerFlutter(rememberLastDirectory: false);
      expect(initTekalyFilePickerFlutter(filePicker: filePicker), filePicker);
      expect(tekalyFilePicker, filePicker);
      expect(tekalyFilePickerFlutter, filePicker);

      /// The interface is the same, a memory picker can take over in tests
      var memory = TekalyFilePickerMemory();
      tekalyFilePicker = memory;
      expect(tekalyFilePicker, memory);
    });
    test('bad arguments', () async {
      var filePicker = TekalyFilePickerFlutter();
      await expectLater(
        filePicker.pickFile(type: TekalyPickFileType.custom),
        throwsArgumentError,
      );
      await expectLater(
        filePicker.pickFiles(
          type: TekalyPickFileType.custom,
          allowedExtensions: [],
        ),
        throwsArgumentError,
      );
    });
  });
  group('toFilePickerFileType', () {
    test('all types', () {
      expect(toFilePickerFileType(TekalyPickFileType.any), fp.FileType.any);
      expect(toFilePickerFileType(TekalyPickFileType.media), fp.FileType.media);
      expect(toFilePickerFileType(TekalyPickFileType.image), fp.FileType.image);
      expect(toFilePickerFileType(TekalyPickFileType.video), fp.FileType.video);
      expect(toFilePickerFileType(TekalyPickFileType.audio), fp.FileType.audio);
      expect(
        toFilePickerFileType(TekalyPickFileType.custom),
        fp.FileType.custom,
      );
    });
  });
  group('TekalyPickedFileXFile', () {
    test('read', () async {
      var file = TekalyPickedFileXFile(
        XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          path: '/tmp/test.bin',
          length: 3,
        ),
      );
      expect(file.name, 'test.bin');
      expect(file.extension, 'bin');
      expect(file.path, '/tmp/test.bin');
      expect(file.uri, Uri.file('/tmp/test.bin'));
      expect(await file.length(), 3);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(await file.readAsByteStream().toList(), [
        [1, 2, 3],
      ]);
    });
  });
}
