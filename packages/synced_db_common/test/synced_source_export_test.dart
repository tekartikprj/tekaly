import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

void main() {
  test('syncedDbExportFileName', () {
    expect(syncedDbExportFileName(12), 'export_12.jsonl');
    expect(syncedDbExportFileName(12, sourceVersion: 0), 'export_12.jsonl');
    expect(syncedDbExportFileName(12, sourceVersion: 2), 'export_v2_12.jsonl');
  });

  test('syncedDbExportFileNameParse', () {
    expect(syncedDbExportFileNameParse('export_12.jsonl'), (
      changeId: 12,
      sourceVersion: null,
    ));
    expect(syncedDbExportFileNameParse('export_v2_12.jsonl'), (
      changeId: 12,
      sourceVersion: 2,
    ));
    for (var name in [
      'export_meta.json',
      'export_012.jsonl',
      'export_v0_12.jsonl',
      'export_v02_12.jsonl',
      'export_12.json',
      'dir/export_12.jsonl',
      'export_99999999999999999999999.jsonl',
    ]) {
      expect(syncedDbExportFileNameParse(name), isNull, reason: name);
    }
  });
}
