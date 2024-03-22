import 'dart:convert';
import 'dart:js_interop';

import 'package:pub_semver/pub_semver.dart';
import 'package:tekartik_platform_browser/context_browser.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart';

import 'download_file.dart';

extension on DownloadFileInfo {
  Blob toBlob() {
    return Blob([data.toJS].toJS, BlobPropertyBag()..type = mimeType);
  }

  String toHref() => URL.createObjectURL(toBlob());

  void applyToAnchor(HTMLAnchorElement anchor) {
    // if (true) {
    if (platformContextBrowser.browser!.isSafari &&
        platformContextBrowser.browser!.version < Version(13, 0, 0)) {
      /*
    window.location.href = imageInfo.url;
    */

      anchor.href = toHref();

      // https://stackoverflow.com/questions/58019463/how-to-detect-device-name-in-safari-on-ios-13-while-it-doesnt-show-the-correct
      //if (platformContextBrowser.browser.isSafari && platformContextBrowser.browser.version < Version(13,0,0)) {
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
    String selector, DownloadFileInfo fileInfo) async {
  var anchor = document.querySelector(selector) as HTMLAnchorElement;
  var base64Context = base64.encode(fileInfo.data);
  // ignore: unsafe_html
  anchor.href =
      'data:${fileInfo.mimeType};base64,$base64Context'; //Image Base64 Goes here
  anchor.download = fileInfo.filename; //File name Here
}
