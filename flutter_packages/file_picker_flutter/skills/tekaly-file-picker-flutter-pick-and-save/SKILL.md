---
name: tekaly-file-picker-flutter-pick-and-save
description: >-
  Use when a flutter app must pick or save files through a dialog
  (TekalyFilePickerFlutter, initTekalyFilePickerFlutter, tekalyFilePicker,
  pickFile, pickFiles, pickImageFile, pickDirectoryPath, saveFile,
  TekalyPickedFilePlatformFile, TekalyPickedFileXFile, toFilePickerFileType)
  with tekaly_file_picker_flutter, the flutter implementation of the
  tekaly_file_picker interface on top of file_picker, including its linux
  file_selector fallback and its in memory test double.
---

# Pick and save files in a flutter app (tekaly_file_picker_flutter)

`tekaly_file_picker_flutter` is the flutter implementation of the
`tekaly_file_picker` interface, on top of the `file_picker` plugin (with a
`file_selector` fallback on linux desktop). The app depends on it; business code
keeps depending on the plugin free `TekalyFilePicker` interface, so it stays
testable.

## Guidelines

* This package is not on pub.dev, depend on it with a git dependency:

  ```yaml
  dependencies:
    tekaly_file_picker_flutter:
      git:
        url: https://github.com/tekartikprj/tekaly
        path: flutter_packages/file_picker_flutter
  ```

* One import is enough: `package:tekaly_file_picker_flutter/file_picker_flutter.dart`
  re-exports the whole `tekaly_file_picker` interface (`TekalyFilePicker`,
  `TekalyPickedFile`, `TekalyPickFileType`, `tekalyFilePicker`) on top of
  `TekalyFilePickerFlutter`, `initTekalyFilePickerFlutter`,
  `tekalyFilePickerFlutter`, `toFilePickerFileType`,
  `TekalyPickedFilePlatformFile` and `TekalyPickedFileXFile`.
* Call `initTekalyFilePickerFlutter()` once at startup (before `runApp`): it
  sets the global `tekalyFilePicker` to the flutter implementation and returns
  it. Pass `filePicker:` to install a customized `TekalyFilePickerFlutter`.
  `tekalyFilePickerFlutter` is the default instance, created on first access.
* Prefer taking a `TekalyFilePicker` as a constructor/parameter in widgets and
  blocs (that is what makes them testable) and keep the global for code that
  cannot receive one. Reading `tekalyFilePicker` before it was initialized
  throws a `StateError`; `tekalyFilePickerOrNull` is the nullable variant.
* `TekalyFilePickerFlutter({useFileSelectorFallback = true,
  rememberLastDirectory = true})`:
  * `useFileSelectorFallback` uses `file_selector` (the gtk dialog) instead of
    `file_picker` on linux desktop, where `file_picker` misbehaves. Set it to
    `false` to always use `file_picker`.
  * `rememberLastDirectory` stores the directory of the last picked or saved
    file in `lastDirectory` and reuses it as the initial directory of the next
    dialog; an explicit `initialDirectory:` always wins.
* Picking: `pickFile()` returns `null` when cancelled, `pickFiles()` returns an
  empty list; both take `type:`, `allowedExtensions:`, `dialogTitle:` and
  `initialDirectory:`. The helpers `pickImageFile()`, `pickAnyFile()` and
  `pickCustomFile(allowedExtensions:)` cover the common cases.
  `TekalyPickFileType.custom` **requires** a non empty `allowedExtensions`
  (lower case, no leading dot) or an `ArgumentError` is thrown.
  `pickDirectoryPath()` returns `null` when cancelled or unsupported (the web).
* Reading a picked file: `readAsBytes()`, `readAsString()` or
  `readAsByteStream()` for big ones, plus `name`, `extension`, `length()`,
  `uri` and `path`. Always read the bytes rather than the path: `path` is
  `null` on the web and can be null on android content uris.
* Saving: `saveFile(fileName:, bytes:, mimeType:, dialogTitle:,
  initialDirectory:)` opens a save dialog, writes the bytes and returns the uri
  of the saved file — `null` when the user cancelled *and* on the web, where
  `file_picker` just downloads the file. `mimeType` defaults to
  `tekalyDefaultMimeType` (`application/octet-stream`). For a plain "give this
  file to the user" flow, prefer `downloadFile()` from `tekaly_file_download`,
  which uses the browser download on the web; see the
  `tekaly-file-download-save-file` skill.
* The linux fallback is transparent: the same `TekalyPickedFile` comes out, just
  backed by an `XFile` (`TekalyPickedFileXFile`) instead of a `PlatformFile`
  (`TekalyPickedFilePlatformFile`). Use those subclasses' `xFile` /
  `platformFile` getters only as an escape hatch for something platform
  specific, and `toFilePickerFileType(type)` to convert a `TekalyPickFileType`
  to a `file_picker` `FileType`.
* Platform setup: nothing on android, linux and windows; on iOS add
  `NSPhotoLibraryUsageDescription` to `Info.plist` when picking
  `image`/`video`/`media`; on macOS add
  `com.apple.security.files.user-selected.read-write` to both the
  `DebugProfile` and `Release` entitlements.
* Anti-patterns: importing `package:file_picker/file_picker.dart` or
  `dart:io`/`package:web` in business code, branching on
  `Platform.isLinux`/`kIsWeb` yourself, keeping a home made "last directory"
  global, and treating a `null` pick result as an error rather than a cancel.
* Testing: widget and unit tests never open a real dialog. Use
  `TekalyFilePickerMemory` from `package:tekaly_file_picker/file_picker_memory.dart`
  (`addFile(name:, bytes:)`, `addTextFile(name:, text:)`, `saveRequests`,
  `cancelled = true`), either injected or assigned to the global
  `tekalyFilePicker`.

## Examples

Startup, then a widget that uses the global picker:

```dart
import 'package:flutter/material.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

void main() {
  initTekalyFilePickerFlutter();
  runApp(const MaterialApp(home: PickImageButton()));
}

class PickImageButton extends StatelessWidget {
  const PickImageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        var file = await tekalyFilePicker.pickImageFile();
        if (file == null) {
          return; // cancelled by the user
        }
        var bytes = await file.readAsBytes();
        debugPrint('${file.name} (${file.extension}): ${bytes.length} bytes');
      },
      child: const Text('Pick an image'),
    );
  }
}
```

An injected picker (what testable code does), picking several files of a custom
type and saving one back:

```dart
import 'dart:convert';

import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

class NotesService {
  final TekalyFilePicker filePicker;

  /// Defaults to the flutter implementation, a memory one in tests.
  NotesService({TekalyFilePicker? filePicker})
    : filePicker = filePicker ?? tekalyFilePickerFlutter;

  Future<List<String>> importNotes() async {
    var files = await filePicker.pickFiles(
      type: TekalyPickFileType.custom,
      allowedExtensions: ['txt', 'md'],
      dialogTitle: 'Import notes',
    );
    return [for (var file in files) await file.readAsString()];
  }

  Future<Uri?> exportNotes(String text) => filePicker.saveFile(
    fileName: 'notes.txt',
    bytes: utf8.encode(text),
    mimeType: 'text/plain',
  );
}
```

A customized picker (no linux fallback, no directory memory) installed as the
global one, and the escape hatch to the underlying plugin objects:

```dart
import 'package:file_picker/file_picker.dart' as fp;
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

Future<void> setupAndPick() async {
  var picker = TekalyFilePickerFlutter(
    useFileSelectorFallback: false,
    rememberLastDirectory: false,
  );
  initTekalyFilePickerFlutter(filePicker: picker);

  var file = await picker.pickAnyFile();
  if (file is TekalyPickedFilePlatformFile) {
    fp.PlatformFile platformFile = file.platformFile;
    print('${platformFile.name} ${platformFile.uri}');
  } else if (file is TekalyPickedFileXFile) {
    print(file.xFile.mimeType); // linux/file_selector
  }
  print(picker.lastDirectory); // null, not remembered here
  print(toFilePickerFileType(TekalyPickFileType.image)); // FileType.image
}
```

Test, with the in memory picker taking over:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

void main() {
  test('the memory picker replaces the flutter one', () async {
    expect(tekalyFilePickerFlutter, isA<TekalyFilePicker>());

    var memory = TekalyFilePickerMemory();
    memory.addTextFile(name: 'notes.txt', text: 'Hello');
    tekalyFilePicker = memory;

    var file = await tekalyFilePicker.pickCustomFile(
      allowedExtensions: ['txt'],
    );
    expect(await file!.readAsString(), 'Hello');

    memory.cancelled = true;
    expect(await tekalyFilePicker.pickAnyFile(), isNull);
  });

  test('custom without extensions is an error', () async {
    await expectLater(
      TekalyFilePickerFlutter().pickFile(type: TekalyPickFileType.custom),
      throwsArgumentError,
    );
  });
}
```
