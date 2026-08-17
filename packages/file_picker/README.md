## tekaly_file_picker

File picker interface, with no flutter, `dart:io` nor web dependency, so that it
can be used from any (testable) business code.

* `tekaly_file_picker` (here): the interface and an in memory implementation.
* [`tekaly_file_picker_flutter`](../../flutter_packages/file_picker_flutter):
  the flutter implementation, on top of
  [`file_picker`](https://pub.dev/packages/file_picker) 12.

Business code only depends on `TekalyFilePicker`/`TekalyPickedFile`, so it never
sees `file_picker`, plugins nor platform channels and can run in a plain
`dart test`.

## Setup

`pubspec.yaml`:

```yaml
  tekaly_file_picker:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/file_picker
```

A flutter app depends on `tekaly_file_picker_flutter` instead, which re-exports
everything below.

## Usage

```dart
import 'package:tekaly_file_picker/file_picker.dart';

Future<void> pickAndUpload(TekalyFilePicker filePicker) async {
  var file = await filePicker.pickImageFile();
  if (file == null) {
    /// Cancelled by the user
    return;
  }
  var bytes = await file.readAsBytes();
  print('${file.name}: ${bytes.length} bytes');
}
```

See [example/tekaly_file_picker_example.dart](example/tekaly_file_picker_example.dart),
runnable with `dart run example/tekaly_file_picker_example.dart`.

### Global picker

A global picker is available for applications that don't want to pass it
around:

```dart
/// Once at startup (`initTekalyFilePickerFlutter()` in a flutter app)
tekalyFilePicker = TekalyFilePickerMemory();

/// Anywhere
var file = await tekalyFilePicker.pickAnyFile();
```

It throws a `StateError` when read before being set. Use
`tekalyFilePickerOrNull` (`null` when not initialized) to use the global picker
when there is one and fall back to your own default otherwise.

## API

### `TekalyFilePicker`

| Method | Result |
| --- | --- |
| `pickFile({type, allowedExtensions, dialogTitle, initialDirectory})` | the picked file, `null` when cancelled |
| `pickFiles({type, allowedExtensions, dialogTitle, initialDirectory})` | the picked files, empty when cancelled |
| `pickDirectoryPath({dialogTitle, initialDirectory})` | the picked directory path, `null` when cancelled or unsupported (the web) |
| `saveFile({fileName, bytes, mimeType, dialogTitle, initialDirectory})` | the uri of the saved file, `null` when cancelled or unknown (the web) |

and the `pickImageFile()`, `pickAnyFile()`,
`pickCustomFile(allowedExtensions: [...])` shortcuts.

`saveFile()` asks the user where to save `bytes`, `fileName` being the suggested
name (extension included) and `mimeType` defaulting to
`tekalyDefaultMimeType` (`application/octet-stream`). Do not rely on the
returned uri to know whether the file was written: the web downloads the file
without ever giving a path back.
[`tekaly_file_download`](../../flutter_packages/file_download) builds on it to
download a file on every platform.

`type` is a `TekalyPickFileType`: `any` (default), `media` (images and videos),
`image`, `video`, `audio` or `custom`. `allowedExtensions` (lower case, without
the leading dot) is required for `custom` and ignored otherwise -
`ArgumentError` is thrown when it is missing or empty.

### `TekalyPickedFile`

| Member | Description |
| --- | --- |
| `name` | file name, including the extension (`my_image.png`) |
| `extension` | lower case extension without the dot (`png`), empty when there is none |
| `uri` | uri of the file, `null` when unknown. Depending on the platform it can be a `file:`, `blob:`, `data:` or `http(s):` uri |
| `path` | local file path, `null` when the file is not on the local disk (the web in particular) |
| `length()` | size in bytes |
| `readAsBytes()` | the whole content at once |
| `readAsByteStream()` | the content, chunk by chunk. Prefer it for big files |
| `readAsString({encoding})` | the whole content decoded, utf-8 by default |

**Never assume `path` is non null**: it is always `null` on the web, and can be
`null` on mobile for a content uri. Read the bytes instead.

### Type helpers

`tekalyImageFileExtensions`, `tekalyVideoFileExtensions`,
`tekalyAudioFileExtensions` and
`tekalyPickFileTypeExtensions(type, [allowedExtensions])` (which returns `null`
for `TekalyPickFileType.any`, i.e. everything matches) are exported, shared by
the implementations and usable to check a file after the fact.

## Testing

`package:tekaly_file_picker/file_picker_memory.dart` provides
`TekalyFilePickerMemory`, a complete implementation holding its files in
memory. The files the simulated user can pick are the ones added to it,
filtered by the requested type, exactly like a real picker would.

```dart
import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';

var filePicker = TekalyFilePickerMemory();
filePicker.addFile(name: 'logo.png', bytes: pngBytes);
filePicker.addTextFile(name: 'notes.txt', text: 'hi');

/// Only matches the image
var file = await filePicker.pickImageFile();
expect(file!.name, 'logo.png');

/// Simulate a user cancelling the dialog
filePicker.cancelled = true;
expect(await filePicker.pickImageFile(), isNull);
filePicker.cancelled = false;

/// Assert what the code under test asked for
expect(filePicker.requests.last.type, TekalyPickFileType.image);

/// Directory picking
filePicker.directoryPath = '/tmp/dir';
expect(await filePicker.pickDirectoryPath(), '/tmp/dir');

/// Saving, nothing is written, the request holds the content
await filePicker.saveFile(fileName: 'export.txt', bytes: utf8.encode('hi'));
expect(filePicker.saveRequests.single.fileName, 'export.txt');

/// Start over
filePicker.clear();
```

| Member | Description |
| --- | --- |
| `files` | the modifiable list of files available for picking |
| `addFile({name, bytes, uri})` | add a file and return it |
| `addTextFile({name, text, uri})` | add a text file and return it |
| `addPickedFile(file)` | add an existing `TekalyPickedFile` and return it |
| `cancelled` | when true, every pick and every save behaves as if the user cancelled |
| `directoryPath` | what `pickDirectoryPath()` returns, and where `saveFile()` pretends to save |
| `requests` | every `TekalyFilePickRequest` received so far, in order |
| `saveRequests` | every `TekalyFileSaveRequest` received so far, in order, with its content |
| `saveUri` | what `saveFile()` returns, built from `directoryPath` when `null` |
| `clear()` | remove all the files and the recorded requests |

`TekalyPickedFileMemory` can also be used on its own, it is a
`TekalyPickedFile` backed by bytes:

```dart
TekalyPickedFileMemory(name: 'test.bin', bytes: [1, 2, 3]);
TekalyPickedFileMemory.fromString(name: 'notes.txt', text: 'hi');

/// With a path, so that `path` and `uri` are set
TekalyPickedFileMemory.file(path: '/tmp/dir/logo.png', bytes: pngBytes);
```

`readAsByteStream()` yields `chunkSize` (64 KB by default) chunks, handy to
exercise chunked reading code.

## Writing another implementation

Implement `TekalyFilePicker` (4 methods) and `TekalyPickedFile`, calling
`checkTekalyPickFileArguments(type: type, allowedExtensions: allowedExtensions)`
first so that the `custom` contract is enforced the same way everywhere.
`TekalyPickedFile.path` has a default implementation deriving it from `uri`
(only when its scheme is `file`), so extending it is usually enough.
