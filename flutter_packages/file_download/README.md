## tekaly_file_download

Flutter file download, on every platform:

* the web: the browser downloads the file
  ([`tekaly_file_download_web`](../../packages/file_download_web)).
* elsewhere: a save dialog asks the user where to put it
  ([`tekaly_file_picker_flutter`](../file_picker_flutter)).

`file_picker` is never used directly here, everything goes through the
`tekaly_file_picker` interface, so a download is testable with
`TekalyFilePickerMemory`.

Runnable playground:
[`flutter_packages/file_download_flutter_example`](../file_download_flutter_example)
(all platforms, every content type, lazy generation).

### Setup

```yaml
  tekaly_file_download:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: flutter_packages/file_download
```

### Usage

```dart
import 'package:tekaly_file_download/download_file.dart';

await downloadFile(
  DownloadFileInfo(filename: 'hello.txt', data: utf8.encode('Hello World')),
);
```

`DownloadFileInfo` deduces the mime type from the filename extension
(`filenameMimeType()`, `application/octet-stream` when unknown), pass `mimeType`
to force it.

The save dialog uses the global `tekalyFilePicker` when it has been initialized
(`initTekalyFilePickerFlutter()`, which an app should do once at startup) and
the default flutter file picker otherwise. Nothing is returned: cancelling the
dialog is not an error, and the web never reports a path.

Images have their own helper, which sets the mime type from the extension (png
or jpeg):

```dart
import 'package:tekaly_file_download/download_image.dart';

await downloadImage(DownloadImageInfo(filename: 'shot.png', data: pngBytes));
```

### On the web

The download is a synthetic anchor click on a blob url, so a browser can block
it when it happens too long after the user gesture (Safari especially).
Generate the content *before* the tap when it matters, or keep an anchor in
`web/index.html` and feed it with `anchorSelectorSetDownloadFileInfo(selector,
fileInfo)` (re-exported here, a no op on the other platforms). The example app
has a 1s lazy button to check how each browser behaves.

### Testing

```dart
import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';

var filePicker = TekalyFilePickerMemory();
tekalyFilePicker = filePicker;

await downloadFile(DownloadFileInfo(filename: 'a.txt', data: bytes));

expect(filePicker.saveRequests.single.fileName, 'a.txt');
```
