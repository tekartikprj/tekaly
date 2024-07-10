import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_source.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

import 'db_sync_record.dart';

class SyncedRecordKey {
  final String store;
  final String key;

  SyncedRecordKey({required this.store, required this.key});

  @override
  int get hashCode => store.hashCode + key.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is SyncedRecordKey) {
      if (other.store != store) {
        return false;
      }
      if (other.key != key) {
        return false;
      }
      return true;
    }
    return false;
  }

  @override
  String toString() => '$store:$key';
}

/// Source in firestore
class SyncedSourceRecordData extends CvModelBase {
  final store = CvField<String>(recordStoreFieldKey);
  final key = CvField<String>(recordKeyFieldKey);
  final deleted = CvField<bool>(recordDeletedFieldKey);

  /// Since this is 2 level deep, content will not be indexed!
  final value = CvField<Model>(recordValueFieldKey);

  /// Some old sync engine don't set the deleted flag correctly
  bool get isDeleted => deleted.v == true || value.v == null;
  @override
  List<CvField> get fields => [store, key, value, deleted];

  SyncedRecordKey get syncedKey =>
      SyncedRecordKey(store: store.v!, key: key.v!);
}

/// Source in firestore
class SyncedSourceRecord extends CvModelBase {
  /// Sync id if any, this is the firestore hence not save in firestore
  final syncId = CvField<String>(syncIdKey);

  /// Server change id
  final syncChangeId = CvField<int>(syncChangeIdKey);

  /// Server timestamp
  final syncTimestamp = CvField<Timestamp>(syncTimestampKey);
  final record = CvModelField<SyncedSourceRecordData>(
      recordFieldKey, (_) => SyncedSourceRecordData());
  //final store = CvField<String>(recordStoreFieldKey);
  //final key = CvField<String>(recordKeyFieldKey);
  //final deleted = CvField<bool>(recordDeletedFieldKey);
  //final value = CvField<Map>(recordValueFieldKey);

  String get recordKey => record.v!.key.v!;
  String get recordStore => record.v!.store.v!;
  bool get isDeleted => record.v!.isDeleted;

  /// Get the reference to the record.
  SyncedDataSourceRef get ref =>
      SyncedDataSourceRef(store: recordStore, key: recordKey, syncId: syncId.v);
  @override
  List<CvField> get fields => [syncId, syncTimestamp, syncChangeId, record];

  SyncedRecordKey get syncedKey =>
      SyncedRecordKey(store: record.v!.store.v!, key: record.v!.key.v!);
}
