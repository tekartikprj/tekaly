import 'dart:convert';

import 'package:tekaly_file_picker/file_picker_memory.dart';

/// A 8x8 red png, used to feed the in memory picker.
final samplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR42mN4'
  'ammKFTEMLQkASbdUwT/V0iMAAAAASUVORK5CYII=',
);

/// An in memory picker, pre-filled with a few files.
///
/// Used to demonstrate that the very same code runs against a mock, without a
/// single dialog nor plugin.
TekalyFilePickerMemory newSampleMemoryFilePicker() {
  var filePicker = TekalyFilePickerMemory(directoryPath: '/memory/dir');
  filePicker.addPickedFile(
    TekalyPickedFileMemory.file(
      path: '/memory/dir/red.png',
      bytes: samplePngBytes,
    ),
  );
  filePicker.addTextFile(
    name: 'notes.txt',
    text: 'Hello from the in memory picker.',
    uri: Uri.file('/memory/dir/notes.txt'),
  );
  filePicker.addTextFile(
    name: 'config.json',
    text: '{"hello": "world"}',
    uri: Uri.file('/memory/dir/config.json'),
  );
  filePicker.addFile(
    name: 'clip.mp4',
    bytes: List.generate(256 * 1024, (index) => index % 256),
    uri: Uri.file('/memory/dir/clip.mp4'),
  );
  return filePicker;
}
