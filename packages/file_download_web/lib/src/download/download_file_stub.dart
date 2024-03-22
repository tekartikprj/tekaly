import 'dart:io';

import 'package:path/path.dart';

import 'download_file.dart';

/// Web only
Future<void> downloadFile(DownloadFileInfo imageInfo) async {
  var file = File(join('.local', 'download', imageInfo.filename));
  file.parent.createSync(recursive: true);
  await file.writeAsBytes(imageInfo.data);
}

/// Web only
void anchorSelectorSetDownloadFileInfo(
    String selector, DownloadFileInfo fileInfo) {
  // no op
}
