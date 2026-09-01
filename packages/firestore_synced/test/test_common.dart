import 'package:tekaly_firestore_synced/synced_firestore_sdb.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

export 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

/// Test document.
class DbTest extends CvFirestoreDocumentBase {
  /// Title.
  final title = CvField<String>('title');

  @override
  CvFields get fields => [title];
}

/// Test collection reference.
CvCollectionReference<DbTest> get testCollectionReference =>
    CvCollectionReference<DbTest>('test');

/// Raw synced info of a document.
Future<CvSyncedFsDocumentSyncedInfo?> rawSyncedInfo(
  Firestore firestore,
  String path,
) async => (await firestore.doc(path).get()).dataOrNull?.syncedInfoOrNull;

/// Local store mirroring the test collection.
final itemStoreRef = SdbStoreRef<String, SdbModel>('item');

/// Local schema, the mirrored store next to the sync bookkeeping stores.
final itemSchema = SdbDatabaseSchema(
  stores: [itemStoreRef.schema(), ...syncedFsSdbSchema.stores],
);

/// Content of the local store.
Future<Map<String, SdbModel>> storeContent(SdbDatabase db) async {
  var records = await itemStoreRef.findRecords(db);
  return {for (var record in records) record.ref.key: record.value};
}
