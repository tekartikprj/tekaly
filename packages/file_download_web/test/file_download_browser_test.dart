@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:tekaly_file_download_web/file_download.dart';
import 'package:tekaly_file_download_web/src/download/download_file_web.dart'
    show downloadFileRevokeDelay;
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'file_download_test.dart';

/// On macOS, a started download keeps headless Chrome alive after the tests
/// complete and `dart test` never exits (CI job cancelled after 6 hours).
bool get _isMacOS => window.navigator.userAgent.contains('Macintosh');

/// Records the blob urls created and revoked.
class _BlobUrlSpy {
  final created = <String>[];
  final revoked = <String>[];
  final JSObject _url;

  /// The original functions, read before being replaced.
  final JSFunction _create;
  final JSFunction _revoke;

  factory _BlobUrlSpy() => _BlobUrlSpy._(globalContext['URL'] as JSObject);

  _BlobUrlSpy._(this._url)
    : _create = _url['createObjectURL'] as JSFunction,
      _revoke = _url['revokeObjectURL'] as JSFunction {
    _url['createObjectURL'] = ((JSAny blob) {
      var url = _create.callAsFunction(_url, blob) as JSString;
      created.add(url.toDart);
      return url;
    }).toJS;
    _url['revokeObjectURL'] = ((JSString url) {
      revoked.add(url.toDart);
      _revoke.callAsFunction(_url, url);
    }).toJS;
  }

  void restore() {
    _url['createObjectURL'] = _create;
    _url['revokeObjectURL'] = _revoke;
  }
}

void main() {
  late _BlobUrlSpy spy;
  setUp(() {
    spy = _BlobUrlSpy();
  });
  tearDown(() {
    spy.restore();
  });
  test('anchorSelectorSetDownloadFileInfo', () {
    var anchor = document.createElement('a') as HTMLAnchorElement;
    anchor.id = 'test-download-anchor';
    document.body!.append(anchor);
    try {
      anchorSelectorSetDownloadFileInfo('#test-download-anchor', textFileInfo);
      expect(anchor.download, 'test.txt');
      expect(anchor.type, 'text/plain');
      expect(anchor.href, startsWith('blob:'));
      expect(spy.created, [anchor.href]);
      expect(spy.revoked, isEmpty);

      // Replacing the content releases the previous blob
      anchorSelectorSetDownloadFileInfo('#test-download-anchor', textFileInfo2);
      expect(anchor.download, 'test2.txt');
      expect(spy.created, hasLength(2));
      expect(anchor.href, spy.created.last);
      expect(spy.revoked, [spy.created.first]);
    } finally {
      anchor.remove();
    }
  });

  test(
    'downloadFile',
    () async {
      var revokeDelay = downloadFileRevokeDelay;
      downloadFileRevokeDelay = Duration.zero;
      try {
        await downloadFile(textFileInfo2);
        expect(spy.created, hasLength(1));
        // The blob is released once the download is started
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(spy.revoked, spy.created);
      } finally {
        downloadFileRevokeDelay = revokeDelay;
      }
    },
    skip: _isMacOS
        ? 'Started download keeps headless Chrome alive on macOS'
        : false,
  );
}
