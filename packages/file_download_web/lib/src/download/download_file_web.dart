import 'dart:convert';
import 'dart:js_interop';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart';

import 'download_file.dart';

extension on DownloadFileInfo {
  Blob toBlob() {
    return Blob([data.toJS].toJS, BlobPropertyBag()..type = mimeType);
  }

  String toHref() => URL.createObjectURL(toBlob());

  void applyToAnchor(HTMLAnchorElement anchor) {
    if (true) {
      // if (platformContextBrowser.browser!.isSafari &&
      //    platformContextBrowser.browser!.version < Version(13, 0, 0)) {

      anchor.href = toHref();

      // https://stackoverflow.com/questions/58019463/how-to-detect-device-name-in-safari-on-ios-13-while-it-doesnt-show-the-correct
      //if (platformContextBrowser.browser.isSafari && platformContextBrowser.browser.version < Version(13,0,0)) {
      // ignore: dead_code
    } else {
      var base64Context = base64.encode(data);

      anchor.href =
          'data:$mimeType;base64,$base64Context'; //Image Base64 Goes here
    }
    anchor.download = filename; //File name Here
    anchor.type = mimeType;
  }
}

Future<void> downloadFile(DownloadFileInfo fileInfo) async {
  var a = document.createElement('a') as HTMLAnchorElement; //Create <a>
  fileInfo.applyToAnchor(a);
  a.click(); //Downloaded file
}

void anchorSelectorSetDownloadFileInfo(
  String selector,
  DownloadFileInfo fileInfo,
) async {
  var anchor = document.querySelector(selector) as HTMLAnchorElement;
  fileInfo.applyToAnchor(anchor);
}
