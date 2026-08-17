## tekaly_file_picker_flutter

Flutter implementation of the [`tekaly_file_picker`](../../packages/file_picker)
interface, on top of [`file_picker`](https://pub.dev/packages/file_picker) 12.

An app depends on this package, its business code only depends on
`tekaly_file_picker`, so it stays free of plugins and platform channels and can
be tested with `TekalyFilePickerMemory`.

Runnable playground:
[`flutter_packages/file_picker_flutter_example`](../file_picker_flutter_example)
(all platforms).

## Setup

`pubspec.yaml`:

```yaml
  tekaly_file_picker_flutter:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: flutter_packages/file_picker_flutter
```

`tekaly_file_picker` is re-exported, so a single import is enough:

```dart
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';
```

## Usage

```dart
/// Once at startup, sets the global `tekalyFilePicker`
void main() {
  initTekalyFilePickerFlutter();
  runApp(const MyApp());
}

/// Anywhere
Future<void> onPickImage() async {
  var file = await tekalyFilePicker.pickImageFile();
  if (file == null) {
    /// Cancelled by the user
    return;
  }
  var bytes = await file.readAsBytes();
  print('${file.name}: ${bytes.length} bytes');
}
```

or without the global, which is what a testable widget/bloc should do - take a
`TekalyFilePicker` and let the caller decide which one:

```dart
var filePicker = TekalyFilePickerFlutter();
var file = await filePicker.pickAnyFile();
```

See the [`tekaly_file_picker` README](../../packages/file_picker/README.md) for
the full `TekalyFilePicker`/`TekalyPickedFile` API.

## `TekalyFilePickerFlutter`

| Constructor parameter | Default | Description |
| --- | --- | --- |
| `useFileSelectorFallback` | `true` | use `file_selector` (gtk) instead of `file_picker` on linux desktop |
| `rememberLastDirectory` | `true` | remember the directory of the last picked file in `lastDirectory` and reuse it as the initial directory of the next pick |

`initTekalyFilePickerFlutter({filePicker})` sets the global `tekalyFilePicker`
and returns it. `tekalyFilePickerFlutter` is the default instance, created on
first access.

### Saving

`saveFile({fileName, bytes, mimeType, dialogTitle, initialDirectory})` opens a
save dialog and writes `bytes`, returning the uri of the saved file (`null` when
cancelled). On the web `file_picker` downloads it and there is no uri to report.
[`tekaly_file_download`](../file_download) wraps it, using the browser download
on the web instead.

### The linux fallback

`file_picker` misbehaves on linux desktop, so `file_selector` (which uses the
gtk dialog) is used there instead. This is transparent: the same
`TekalyPickedFile` comes out, backed by an `XFile`
(`TekalyPickedFileXFile`) rather than a `PlatformFile`
(`TekalyPickedFilePlatformFile`). Pass `useFileSelectorFallback: false` to
always use `file_picker`. `file_selector` only returns a location for a save, so
`saveFile()` writes the content itself there.

The choice is made through a conditional import
(`file_selector_io.dart` / `file_selector_web.dart`), so a web build never
pulls `dart:io` in.

### Escape hatches

`TekalyPickedFilePlatformFile.platformFile` and `TekalyPickedFileXFile.xFile`
expose the underlying object when something platform specific is needed, and
`toFilePickerFileType()` converts a `TekalyPickFileType` to a `file_picker`
`FileType`.

## Platform setup

| Platform | Needed |
| --- | --- |
| Android | nothing, `file_picker` 12 uses the storage access framework |
| iOS | `NSPhotoLibraryUsageDescription` in `Info.plist` when picking `image`/`video`/`media` |
| macOS | `com.apple.security.files.user-selected.read-write` in the entitlements (both `DebugProfile` and `Release`) |
| linux | the gtk dialog, nothing to declare |
| Windows | nothing |
| Web | nothing. `path` is always `null` there, read the bytes |

See the example app for the actual files.

## Testing

Business code takes a `TekalyFilePicker`, so a widget test drives the in memory
implementation instead of a real dialog:

```dart
import 'package:tekaly_file_picker/file_picker_memory.dart';

var filePicker = TekalyFilePickerMemory();
filePicker.addFile(name: 'logo.png', bytes: pngBytes);

/// Either injected, or through the global
tekalyFilePicker = filePicker;

await tester.tap(find.text('Pick an image'));
await tester.pumpAndSettle();
expect(find.text('logo.png'), findsOneWidget);
```

`file_picker_flutter_example/test/widget_test.dart` does exactly that.

## Migrating from raw `file_picker`

| Before | After |
| --- | --- |
| `FilePicker.pickFile(type: FileType.image)` | `tekalyFilePicker.pickImageFile()` |
| `FilePicker.pickFiles(type: FileType.custom, allowedExtensions: [...])` | `tekalyFilePicker.pickFiles(type: TekalyPickFileType.custom, allowedExtensions: [...])` |
| `FilePicker.getDirectoryPath()` | `tekalyFilePicker.pickDirectoryPath()` |
| `FilePicker.saveFile(fileName: ..., bytes: ...)` | `tekalyFilePicker.saveFile(fileName: ..., bytes: ...)`, or `downloadFile()` (`tekaly_file_download`) |
| `PlatformFile` | `TekalyPickedFile` (same `name`/`path`/`uri`/`length`/`readAsBytes`/`readAsByteStream`) |
| a hand written linux/`file_selector` branch | nothing, it is built in |
| a `lastDir` global | `TekalyFilePickerFlutter.lastDirectory`, applied automatically |
