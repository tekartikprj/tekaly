---
name: tekaly-file-picker-pick-files
description: >-
  Use when business code needs to let the user pick or save files without
  depending on flutter, dart:io or the web (TekalyFilePicker,
  TekalyPickedFile) and when testing it with the in memory picker.
---

# Platform agnostic file picker (tekaly_file_picker)

## Guidelines

* Depend on `TekalyFilePicker` / `TekalyPickedFile` only
  (`package:tekaly_file_picker/file_picker.dart`); never import
  `file_picker` (pub) or platform channels from business code. A flutter app
  depends on `tekaly_file_picker_flutter` instead, which re-exports this
  package and provides the implementation.
* Pick with the extension helpers: `pickImageFile()`, `pickAnyFile()`,
  `pickCustomFile(allowedExtensions:)`, `pickFiles(type:)` (multiple), or the
  raw `pickFile(type:, allowedExtensions:, allowMultiple:)`. `null` (or an
  empty list) means the user cancelled: always handle it.
* Read a picked file with `readAsBytes()`, `readAsString()` or
  `readAsByteStream()` (large files); `name`, `extension`, `length()` and
  `uri`/`path` (null on the web) describe it.
* `saveFile(fileName:, bytes:)` and `pickDirectoryPath()` are available where
  the platform supports them (check the returned null).
* Use the global `tekalyFilePicker` (set once at startup, e.g.
  `initTekalyFilePickerFlutter()` in flutter or
  `tekalyFilePicker = TekalyFilePickerMemory()` in tests) only in application
  code that cannot receive the picker; prefer passing it.
* In tests use `TekalyFilePickerMemory()` from `file_picker_memory.dart`:
  `addFile(name:, bytes:)`, `addTextFile(name:, text:)`, then the picker
  returns the matching files; set `cancelled = true` to simulate a cancel.

## Examples

```dart
import 'package:tekaly_file_picker/file_picker.dart';

Future<String?> pickAndDescribeImage(TekalyFilePicker filePicker) async {
  var file = await filePicker.pickImageFile();
  if (file == null) {
    return null; // cancelled
  }
  var bytes = await file.readAsBytes();
  return '${file.name} (${file.extension}): ${bytes.length} byte(s)';
}
```

```dart
import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';
import 'package:test/test.dart';

void main() {
  test('pick image', () async {
    var filePicker = TekalyFilePickerMemory();
    filePicker.addFile(name: 'logo.png', bytes: [137, 80, 78, 71]);
    filePicker.addTextFile(name: 'notes.txt', text: 'Hello');

    expect(await pickAndDescribeImage(filePicker), 'logo.png (png): 4 byte(s)');
    var text = await filePicker.pickCustomFile(allowedExtensions: ['txt']);
    expect(await text!.readAsString(), 'Hello');

    filePicker.cancelled = true;
    expect(await filePicker.pickAnyFile(), isNull);
  });
}
```
