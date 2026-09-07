@TestOn('browser')
library;

import 'package:tekaly_file_download_web/file_download.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'file_download_test.dart';

/// On macOS, a started download keeps headless Chrome alive after the tests
/// complete and `dart test` never exits (CI job cancelled after 6 hours).
bool get _isMacOS => window.navigator.userAgent.contains('Macintosh');

void main() {
  test('anchorSelectorSetDownloadFileInfo', () {
    var anchor = document.createElement('a') as HTMLAnchorElement;
    anchor.id = 'test-download-anchor';
    document.body!.append(anchor);
    try {
      anchorSelectorSetDownloadFileInfo('#test-download-anchor', textFileInfo);
      expect(anchor.download, 'test.txt');
      expect(anchor.type, 'text/plain');
      expect(anchor.href, startsWith('blob:'));
    } finally {
      anchor.remove();
    }
  });

  test(
    'downloadFile',
    () async {
      await downloadFile(textFileInfo2);
    },
    skip: _isMacOS
        ? 'Started download keeps headless Chrome alive on macOS'
        : false,
  );
}
