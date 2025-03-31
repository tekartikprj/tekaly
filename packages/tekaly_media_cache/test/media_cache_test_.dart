import 'package:tekaly_media_cache/media_cache.dart';
import 'package:test/test.dart';

void main() {
  test('key', () {
    expect(TekalyMediaKey.name('test').toString(), 'Key(test)');
  });
}
