import 'dart:convert';
import 'dart:typed_data';

import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';
import 'package:test/test.dart';

void main() {
  group('TekalyPickedFileMemory', () {
    test('bytes', () async {
      var file = TekalyPickedFileMemory(name: 'test.bin', bytes: [1, 2, 3]);
      expect(file.name, 'test.bin');
      expect(file.extension, 'bin');
      expect(file.uri, isNull);
      expect(file.path, isNull);
      expect(await file.length(), 3);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(await file.readAsByteStream().toList(), [
        [1, 2, 3],
      ]);
    });
    test('empty', () async {
      var file = TekalyPickedFileMemory(name: 'empty', bytes: []);
      expect(file.extension, '');
      expect(await file.length(), 0);
      expect(await file.readAsBytes(), isEmpty);
      expect(await file.readAsByteStream().toList(), isEmpty);
    });
    test('chunks', () async {
      var file = TekalyPickedFileMemory(
        name: 'test.bin',
        bytes: [1, 2, 3, 4, 5],
        chunkSize: 2,
      );
      expect(await file.readAsByteStream().toList(), [
        [1, 2],
        [3, 4],
        [5],
      ]);
    });
    test('fromString', () async {
      var file = TekalyPickedFileMemory.fromString(
        name: 'test.txt',
        text: 'héllo',
      );
      expect(file.extension, 'txt');
      expect(await file.readAsBytes(), utf8.encode('héllo'));
      expect(await file.readAsString(), 'héllo');
    });
    test('file', () async {
      var file = TekalyPickedFileMemory.file(
        path: '/tmp/dir/My Image.PNG',
        bytes: [1],
      );
      expect(file.name, 'My Image.PNG');
      expect(file.extension, 'png');
      expect(file.uri, Uri.file('/tmp/dir/My Image.PNG'));
      expect(file.path, '/tmp/dir/My Image.PNG');
    });
    test('is a TekalyPickedFile', () {
      expect(
        TekalyPickedFileMemory(name: 'test', bytes: <int>[]),
        isA<TekalyPickedFile>(),
      );
      expect(
        TekalyPickedFileMemory(
          name: 'test',
          bytes: Uint8List.fromList([1]),
        ).bytes,
        [1],
      );
    });
  });
  group('TekalyFilePickerMemory', () {
    late TekalyFilePickerMemory filePicker;

    setUp(() {
      filePicker = TekalyFilePickerMemory();
      filePicker.addFile(name: 'logo.png', bytes: [1, 2, 3]);
      filePicker.addTextFile(name: 'notes.txt', text: 'hi');
      filePicker.addFile(name: 'clip.mp4', bytes: [4]);
      filePicker.addFile(name: 'song.mp3', bytes: [5]);
    });

    test('pickAnyFile', () async {
      var file = await filePicker.pickAnyFile();
      expect(file!.name, 'logo.png');
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(filePicker.requests.single.type, TekalyPickFileType.any);
      expect(filePicker.requests.single.multiple, isFalse);
    });
    test('pickImageFile', () async {
      var file = await filePicker.pickImageFile();
      expect(file!.name, 'logo.png');
      expect(filePicker.requests.single.type, TekalyPickFileType.image);
    });
    test('pickFile video/audio/media', () async {
      expect(
        (await filePicker.pickFile(type: TekalyPickFileType.video))!.name,
        'clip.mp4',
      );
      expect(
        (await filePicker.pickFile(type: TekalyPickFileType.audio))!.name,
        'song.mp3',
      );
      expect(
        (await filePicker.pickFiles(
          type: TekalyPickFileType.media,
        )).map((file) => file.name),
        ['logo.png', 'clip.mp4'],
      );
    });
    test('pickCustomFile', () async {
      var file = await filePicker.pickCustomFile(allowedExtensions: ['TXT']);
      expect(file!.name, 'notes.txt');
      expect(await file.readAsString(), 'hi');
      expect(
        await filePicker.pickCustomFile(allowedExtensions: ['pdf']),
        isNull,
      );
    });
    test('pickCustomFile requires extensions', () async {
      expect(
        () => filePicker.pickFile(type: TekalyPickFileType.custom),
        throwsArgumentError,
      );
      expect(
        () => filePicker.pickFile(
          type: TekalyPickFileType.custom,
          allowedExtensions: [],
        ),
        throwsArgumentError,
      );
    });
    test('pickFiles', () async {
      expect((await filePicker.pickFiles()).map((file) => file.name), [
        'logo.png',
        'notes.txt',
        'clip.mp4',
        'song.mp3',
      ]);
      expect(filePicker.requests.single.multiple, isTrue);
    });
    test('no matching file', () async {
      filePicker.clear();
      filePicker.addTextFile(name: 'notes.txt', text: 'hi');
      expect(await filePicker.pickImageFile(), isNull);
      expect(
        await filePicker.pickFiles(type: TekalyPickFileType.image),
        isEmpty,
      );
    });
    test('cancelled', () async {
      filePicker.cancelled = true;
      expect(await filePicker.pickAnyFile(), isNull);
      expect(await filePicker.pickFiles(), isEmpty);
      expect(await filePicker.pickDirectoryPath(), isNull);

      /// Requests are still recorded
      expect(filePicker.requests.length, 2);
    });
    test('pickDirectoryPath', () async {
      expect(await filePicker.pickDirectoryPath(), isNull);
      filePicker.directoryPath = '/tmp/dir';
      expect(await filePicker.pickDirectoryPath(), '/tmp/dir');
    });
    test('requests', () async {
      await filePicker.pickFile(
        dialogTitle: 'Pick one',
        initialDirectory: '/tmp',
      );
      var request = filePicker.requests.single;
      expect(request.dialogTitle, 'Pick one');
      expect(request.initialDirectory, '/tmp');
      expect(request.allowedExtensions, isNull);
    });
    test('is a TekalyFilePicker', () {
      expect(filePicker, isA<TekalyFilePicker>());
    });
    test('saveFile', () async {
      expect(
        await filePicker.saveFile(
          fileName: 'saved.txt',
          bytes: utf8.encode('Hello World'),
          mimeType: 'text/plain',
          dialogTitle: 'Save it',
          initialDirectory: '/tmp',
        ),
        Uri.parse('saved.txt'),
      );
      var request = filePicker.saveRequests.single;
      expect(request.fileName, 'saved.txt');
      expect(utf8.decode(request.bytes), 'Hello World');
      expect(request.mimeType, 'text/plain');
      expect(request.dialogTitle, 'Save it');
      expect(request.initialDirectory, '/tmp');

      /// The uri is built from directoryPath when there is one
      filePicker.directoryPath = '/tmp/dir';
      expect(
        await filePicker.saveFile(fileName: 'saved.txt', bytes: Uint8List(0)),
        Uri.file('/tmp/dir/saved.txt', windows: false),
      );

      /// or forced
      filePicker.saveUri = Uri.parse('blob:saved');
      expect(
        await filePicker.saveFile(fileName: 'saved.txt', bytes: Uint8List(0)),
        Uri.parse('blob:saved'),
      );
      expect(filePicker.saveRequests.length, 3);
    });
    test('saveFile cancelled', () async {
      filePicker.cancelled = true;
      expect(
        await filePicker.saveFile(fileName: 'saved.txt', bytes: Uint8List(0)),
        isNull,
      );

      /// Cancelled or not, the request is recorded
      expect(filePicker.saveRequests.single.fileName, 'saved.txt');
    });
    test('clear', () async {
      filePicker.addTextFile(name: 'notes.txt', text: 'Hello');
      await filePicker.pickFile();
      await filePicker.saveFile(fileName: 'saved.txt', bytes: Uint8List(0));
      filePicker.clear();
      expect(filePicker.files, isEmpty);
      expect(filePicker.requests, isEmpty);
      expect(filePicker.saveRequests, isEmpty);
    });
  });
  group('tekalyFilePicker', () {
    test('global', () async {
      expect(tekalyFilePickerOrNull, isNull);
      expect(() => tekalyFilePicker, throwsStateError);
      var memory = TekalyFilePickerMemory();
      tekalyFilePicker = memory;
      expect(tekalyFilePicker, memory);
      expect(tekalyFilePickerOrNull, memory);
    });
  });
}
