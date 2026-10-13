import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekaly_synced_db_common_test/synced_source_firestore_test_common.dart';
import 'package:test/test.dart';

CvSyncedSourceRecord _record(String key, {bool deleted = false}) =>
    CvSyncedSourceRecord()
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = 'test'
        ..key.v = key
        ..deleted.v = deleted
        ..value.v = {'name': key});

void main() {
  for (var entry in <String, SyncedSource Function()>{
    'memory': SyncedSourceMemory.new,
    'firestore': newInMemorySyncedSourceFirestore,
  }.entries) {
    test(
      '${entry.key} getAllSourceRecordList pages of deleted records',
      () async {
        var source = entry.value();
        await source.putSourceRecord(_record('r1'));
        await source.putSourceRecord(_record('r2'));
        await source.putSourceRecord(_record('r1', deleted: true));
        await source.putSourceRecord(_record('r2', deleted: true));
        await source.putSourceRecord(_record('r3'));
        await source.putSourceRecord(_record('r4'));
        // A page of 2 can hold only deleted records
        var list = await source.getAllSourceRecordList(stepLimit: 2);
        expect(list.list.map((record) => record.recordKey), ['r3', 'r4']);
        expect(list.lastChangeId, 6);
        await source.close();
      },
    );
  }
}
