## tekaly_file_picker_flutter_example

Playground of the [`tekaly_file_picker`](../../packages/file_picker) API, on
every platform Flutter supports: Android, iOS, linux, macOS, web and Windows.

```
flutter run             # the current device
flutter run -d chrome   # the web, where `path` is always null
flutter run -d linux    # the file_selector (gtk) fallback
flutter test            # widget tests driving the in memory picker
```

## What it shows

* **Implementation switch**: the same screen drives either
  `TekalyFilePickerFlutter` (real dialogs) or `TekalyFilePickerMemory` (no
  dialog, no plugin - what tests use). Nothing else in the code changes, which
  is the whole point of the interface.
* **Request**: every `TekalyPickFileType` (`any`, `media`, `image`, `video`,
  `audio`, `custom`), `allowedExtensions`, `dialogTitle` and
  `initialDirectory`.
* **Actions**: `pickFile()`, `pickFiles()`, `pickDirectoryPath()`, and the
  `ArgumentError` you get when `custom` is used without extension.
* **Result**: `name`, `extension`, `path` (null on the web), `uri`, `length()`,
  the concrete `runtimeType` (`TekalyPickedFilePlatformFile`,
  `TekalyPickedFileXFile` on linux, `TekalyPickedFileMemory` for the mock),
  `readAsBytes()` vs `readAsByteStream()` (with the chunk count), and an image
  preview.
* **Mock specifics**: the `cancelled` switch, and the requests the picker
  recorded, which a test asserts on.

## Files

| File | Content |
| --- | --- |
| `lib/main.dart` | `initTekalyFilePickerFlutter()` and the app |
| `lib/src/playground_screen.dart` | the playground, the only place that calls the picker |
| `lib/src/picked_file_tile.dart` | everything a `TekalyPickedFile` exposes |
| `lib/src/sample_files.dart` | the files the in memory picker offers |
| `test/widget_test.dart` | widget tests, running the screen against the mock |

## Platform setup

Beyond `flutter create` defaults, only two things were added, both needed by
`file_picker` itself:

* `ios/Runner/Info.plist`: `NSPhotoLibraryUsageDescription`, required to pick
  `image`/`video`/`media`.
* `macos/Runner/{DebugProfile,Release}.entitlements`:
  `com.apple.security.files.user-selected.read-write`, required to read what
  the user picked from the sandbox.
