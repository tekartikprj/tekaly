import 'dart:async';
import 'dart:js_interop';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart';

import 'download_file.dart';

/// Delay before the blob url of a started download is revoked: the browser
/// might still be reading it right after the click (not exported, changed by
/// tests only).
var downloadFileRevokeDelay = const Duration(seconds: 40);

extension on DownloadFileInfo {
  Blob toBlob() {
    return Blob([data.toJS].toJS, BlobPropertyBag()..type = mimeType);
  }

  String toHref() => URL.createObjectURL(toBlob());

  void applyToAnchor(HTMLAnchorElement anchor) {
    anchor.href = toHref();
    anchor.download = filename; //File name Here
    anchor.type = mimeType;
  }
}

/// Revoke the blob url held by [anchor], if any.
void _revokeAnchorHref(HTMLAnchorElement anchor) {
  var href = anchor.href;
  if (href.startsWith('blob:')) {
    URL.revokeObjectURL(href);
  }
}

Future<void> downloadFile(DownloadFileInfo fileInfo) async {
  var a = document.createElement('a') as HTMLAnchorElement; //Create <a>
  fileInfo.applyToAnchor(a);
  a.click(); //Downloaded file
  // The download is started, release the blob once the browser had time to
  // read it.
  Timer(downloadFileRevokeDelay, () => _revokeAnchorHref(a));
}

void anchorSelectorSetDownloadFileInfo(
  String selector,
  DownloadFileInfo fileInfo,
) {
  var anchor = document.querySelector(selector) as HTMLAnchorElement;
  // The anchor can be clicked again and again: its blob url is kept until it
  // is replaced.
  _revokeAnchorHref(anchor);
  fileInfo.applyToAnchor(anchor);
}
