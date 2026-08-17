## tekaly_file_download_flutter_example

Playground of [`tekaly_file_download`](../file_download) (`downloadFile` and
`downloadImage`), on every platform Flutter supports: Android, iOS, linux, macOS,
web and Windows.

```
flutter run             # the current device, a save dialog
flutter run -d chrome   # the web, a browser download
flutter run -d linux    # the file_selector (gtk) save dialog
flutter test            # widget tests driving the in memory file picker
```

## What it shows

* **Every content type**: text, json, csv, markdown, html, yaml, calendar
  (`.ics`), pdf, png, jpeg, svg, a file with no extension at all, and a sized
  big text / binary content (`size (kB)` field). Each one shows what
  `DownloadFileInfo` deduces as mime type, which is where `.csv` (unknown, hence
  an explicit `mimeType`), `.md` and the extension-less file get interesting.
* **Lazy generation**: the `after 1s` buttons generate the content *one second
  after* the tap, which is what any real app doing some work (reading a file,
  calling an api, encoding an image) before downloading does. On the web the
  download is a synthetic anchor click, so it can be blocked when it happens too
  long after the user gesture (Safari especially) - compare the immediate and the
  lazy buttons in each browser. When it is blocked, generate the content
  *before* the tap, or keep an anchor around and feed it with
  `anchorSelectorSetDownloadFileInfo()` (`tekaly_file_download_web`).
* **`downloadFile` vs `downloadImage`**: `DownloadImageInfo` only knows png and
  jpeg (anything else ends up as `image/jpg`), `DownloadFileInfo` deduces the
  mime type from the extension or takes the one you give it.
* **Where it lands**: the browser download on the web, a save dialog through
  `tekaly_file_picker_flutter` elsewhere, with the picker currently in use.
* **A log** of every call, with the generation time and the total duration, and
  the error when there is one (cancelling a save dialog is not an error).

## Files

| File | Content |
| --- | --- |
| `lib/main.dart` | `initTekalyFilePickerFlutter()` and the app |
| `lib/src/download_playground_screen.dart` | the playground, the only place that calls `downloadFile`/`downloadImage` |
| `lib/src/sample_content.dart` | the contents to download, generated on the fly |
| `lib/src/download_log.dart` | the log of the calls |
| `test/widget_test.dart` | widget tests, saving through `TekalyFilePickerMemory` |

## Testing a download

Not on the web, `downloadFile` saves through the global `tekalyFilePicker`, so a
widget test needs nothing but an in memory picker - no dialog, no plugin:

```dart
var filePicker = TekalyFilePickerMemory();
tekalyFilePicker = filePicker;

await tester.tap(find.text('downloadFile'));
await tester.pumpAndSettle();

var request = filePicker.saveRequests.single;
expect(request.fileName, 'hello.txt');
expect(request.mimeType, 'text/plain');
```

## Platform setup

`flutter create` defaults, plus the one thing `file_picker` needs to write from
the macOS sandbox:

* `macos/Runner/{DebugProfile,Release}.entitlements`:
  `com.apple.security.files.user-selected.read-write`.

Nothing else, no permission is needed to save a file the user picked.
