import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:pub_semver/pub_semver.dart';
import 'package:tekartik_platform_browser/context_browser.dart';
import 'download_image.dart';

void downloadImage(DownloadImageInfo imageInfo) {
  // if (true) {
  if (platformContextBrowser.browser!.isSafari &&
      platformContextBrowser.browser!.version < Version(13, 0, 0)) {
    /*
    window.location.href = imageInfo.url;
    */

    var blob = Blob([imageInfo.data], imageInfo.mimeType);
    var a = document.createElement('a') as AnchorElement; //Create <a>
    // ignore: unsafe_html
    a.href = Url.createObjectUrlFromBlob(blob).toString();
    a.download = imageInfo.filename; //File name Here
    a.click(); //Downloaded file

    // https://stackoverflow.com/questions/58019463/how-to-detect-device-name-in-safari-on-ios-13-while-it-doesnt-show-the-correct
    //if (platformContextBrowser.browser.isSafari && platformContextBrowser.browser.version < Version(13,0,0)) {
  } else {
    var base64Context = base64.encode(imageInfo.data);

    var a = document.createElement('a') as AnchorElement; //Create <a>
    // ignore: unsafe_html
    a.href =
        'data:${imageInfo.mimeType};base64,$base64Context'; //Image Base64 Goes here
    a.download = imageInfo.filename; //File name Here
    a.click(); //Downloaded file
  }
}
