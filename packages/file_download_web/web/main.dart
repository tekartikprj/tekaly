import 'dart:convert';

import 'package:tekaly_file_download_web/file_download.dart';

import 'package:web/web.dart';

var textFileInfo = DownloadFileInfo(
  filename: 'test.txt',
  data: utf8.encode('Hello World'),
);
void main() {
  final now = DateTime.now();
  final element = document.querySelector('#output') as HTMLDivElement;
  element.text =
      'The time is ${now.hour}:${now.minute}'
      ' and your Dart web app is running!';
  var button = document.querySelector('#text-file-button') as HTMLButtonElement;
  EventStreamProviders.clickEvent.forTarget(button).listen((event) {
    print('clicked $textFileInfo');
    downloadFile(textFileInfo);
  });
  anchorSelectorSetDownloadFileInfo('#text-file-link', textFileInfo);
}
