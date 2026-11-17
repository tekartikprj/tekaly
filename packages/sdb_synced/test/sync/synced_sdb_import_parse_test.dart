import 'dart:convert';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:test/test.dart';

import 'synced_source_test_common.dart';

final _myStoreRef = SdbStoreRef<String, SdbModel>('my_store');

final _schema = SdbDatabaseSchema(
  stores: [_myStoreRef.schema(), ...syncedSdbMetaSchema.stores],
);

SyncedSdbOptions _newOptions() => SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(version: 1, schema: _schema),
);

void main() {
  group('parseTekalyExportLines', () {
    test('export of a synced db', () async {
      var syncedSdb = SyncedSdb.newInMemory(options: _newOptions());
      var db = await syncedSdb.database;
      await _myStoreRef.record('item_1').put(db, {'test': 123});
      await _myStoreRef.record('item_2').put(db, {
        'ts': SdbTimestamp(1, 2000),
        'blob': SdbBlob.fromList([1, 2, 3]),
      });
      await SyncedSdbSynchronizer(
        db: syncedSdb,
        source: newInMemorySyncedSourceMemory(),
      ).sync();
      var jsonl = await syncedSdb.exportToJsonlString();
      await syncedSdb.close();

      var parsed = parseTekalyExportLines(decodeTekalyExportLines(jsonl));
      expect(parsed.syncMeta!['lastChangeId'], 2);
      expect(parsed.stores.keys, ['my_store']);
      var records = parsed.stores['my_store']!;
      expect(records['item_1'], {'test': 123});
      var item2 = records['item_2'] as Map;
      expect(item2['ts'], SdbTimestamp(1, 2000));
      expect(item2['blob'], isA<SdbBlob>());
      expect((item2['blob'] as SdbBlob).bytes, [1, 2, 3]);
    });

    test('store without records, no sync meta', () {
      var parsed = parseTekalyExportLines([
        {'tekaly_export': 1, 'version': 1},
        {'store': 'empty_store'},
        {'store': 'my_store'},
        [
          'k1',
          {'a': 1},
        ],
      ]);
      expect(parsed.syncMeta, isNull);
      expect(parsed.stores, {
        'empty_store': <String, Object?>{},
        'my_store': {
          'k1': {'a': 1},
        },
      });
    });

    test('invalid', () {
      expect(() => parseTekalyExportLines([]), throwsFormatException);
      expect(
        () => parseTekalyExportLines([
          {'store': 'my_store'},
        ]),
        throwsFormatException,
      );
      expect(
        () => parseTekalyExportLines([
          {'tekaly_export': 2},
        ]),
        throwsFormatException,
      );
    });
  });

  group('decodeTekalyExportLines', () {
    var lines = [
      {'tekaly_export': 1, 'version': 1},
      {'store': 'my_store'},
      [
        'k1',
        {'a': 1},
      ],
    ];
    test('jsonl, json array, lines', () {
      var jsonl = lines.map(jsonEncode).join('\n');
      expect(decodeTekalyExportLines(jsonl), lines);
      expect(decodeTekalyExportLines('\n$jsonl\n'), lines);
      expect(decodeTekalyExportLines(jsonEncode(lines)), lines);
      expect(decodeTekalyExportLines(lines), same(lines));
    });

    test('invalid', () {
      expect(() => decodeTekalyExportLines(''), throwsFormatException);
      expect(() => decodeTekalyExportLines(1), throwsFormatException);
      expect(() => decodeTekalyExportLines('not json'), throwsFormatException);
    });
  });
}
