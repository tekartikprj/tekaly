---
name: tekaly-file-download-web-download
description: >-
  Use when a dart web or flutter web app must let the user download generated
  bytes as a file (downloadFile, DownloadFileInfo, anchor download links) with
  tekaly_file_download_web.
---

# Download a file in the browser (tekaly_file_download_web)

## Guidelines

* Import `package:tekaly_file_download_web/file_download.dart` from any code:
  the conditional import picks the browser implementation on the web and a
  stub elsewhere (the stub writes the file under `.local/download/`, handy in
  vm tests).
* Build a `DownloadFileInfo(filename:, data:, mimeType:)` with the proper
  file extension; `mimeType` defaults to `filenameMimeType(filename)`
  (extension based, `application/octet-stream` when unknown).
* `downloadFile(info)` creates a temporary anchor and clicks it: call it from
  a user gesture handler (button tap), browsers may block downloads started
  outside one.
* `anchorSelectorSetDownloadFileInfo('#my-link', info)` configures an existing
  `<a>` element so a plain click downloads the content (web only, no-op
  elsewhere).
* Prefer `filenameMimeType` over hard coding mime types when the file name is
  known.

## Examples

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:tekaly_file_download_web/file_download.dart';

Future<void> exportCsv(List<List<String>> rows) async {
  var csv = rows.map((row) => row.join(',')).join('\n');
  await downloadFile(
    DownloadFileInfo(
      filename: 'export.csv', // mimeType: text/csv
      data: utf8.encode(csv),
    ),
  );
}

void setupDownloadLink(List<int> pngBytes) {
  anchorSelectorSetDownloadFileInfo(
    '#download-logo',
    DownloadFileInfo(filename: 'logo.png', data: Uint8List.fromList(pngBytes)),
  );
}
```
