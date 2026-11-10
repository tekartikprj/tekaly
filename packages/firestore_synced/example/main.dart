// ignore_for_file: avoid_print

// A tracked firestore collection mirrored into a local sdb store, all in
// memory: run it with `dart run example/main.dart`.
import 'package:tekaly_firestore_synced/synced_firestore_sdb.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

/// A document of the `item` collection.
class DbItem extends CvFirestoreDocumentBase {
  final title = CvField<String>('title');

  @override
  CvFields get fields => [title];
}

/// The local store mirroring the `item` collection.
final itemStoreRef = SdbStoreRef<String, SdbModel>('item');

Future<void> main() async {
  cvAddConstructors([DbItem.new]);

  // Writer side: any Firestore (here in memory).
  var firestore = newFirestoreMemory();
  var items = SyncedFsCollection(
    firestore: firestore,
    collection: CvCollectionReference<DbItem>('item'),
  );
  await items.setDoc('k1', DbItem()..title.v = 'hello');
  var id = await items.addDoc(DbItem()..title.v = 'added');

  // Consumer side: a local sdb database (here in memory).
  var db = await newSdbFactoryMemory().openDatabase(
    'app.db',
    options: SdbOpenDatabaseOptions(
      version: 1,
      schema: SdbDatabaseSchema(
        stores: [itemStoreRef.schema(), ...syncedFsSdbSchema.stores],
      ),
    ),
  );
  var mirror = SyncedFsSdbSynchronizer(
    source: items.source,
    database: db,
    store: itemStoreRef,
  );
  // The first sync is a full one.
  print(await mirror.sync());

  // Then only the changes are read.
  await items.deleteDoc(id);
  await items.setDoc('k2', DbItem()..title.v = 'world');
  print(await mirror.sync());

  for (var record in await itemStoreRef.findRecords(db)) {
    print('${record.ref.key}: ${record.value}');
  }
  await db.close();
}
