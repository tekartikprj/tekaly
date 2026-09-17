import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

void main() {
  group('synced_source_codec', () {
    test('encode/decode', () {
      expect(syncedDbValueToJsonEncodable(null), isNull);
      expect(syncedDbValueFromJsonEncodable(null), isNull);
      var value = {
        'int': 1,
        'text': 'test',
        'list': [1, 'a'],
        'ts': SyncedDbTimestamp(1, 2000),
        'blob': SyncedDbBlob.fromList([1, 2, 3]),
      };
      var encoded = syncedDbValueToJsonEncodable(value);
      expect(encoded, {
        'int': 1,
        'text': 'test',
        'list': [1, 'a'],
        'ts': {r'$timestamp': '1970-01-01T00:00:01.000002Z'},
        'blob': {r'$blob': 'AQID'},
      });
      expect(syncedDbValueFromJsonEncodable(encoded), value);
    });
  });
}
