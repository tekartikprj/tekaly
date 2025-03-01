import 'package:tekaly_firestore_synced/src/synced_fs_collection.dart';

import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

class _Test extends CvFirestoreDocumentBase {
  final title = CvField<String>('title');
  @override
  CvFields get fields => [title];
}

void main() {
  cvAddConstructors([_Test.new]);
  group('synced_fs_collection', () {
    late Firestore firestore;

    setUp(() {
      firestore = newFirestoreMemory(); //.debugQuickLoggerWrapper();
    });

    test('get/put/add/delete', () async {
      var collection = CvCollectionReference<_Test>('test');
      var coll = SyncedFsCollection(
        firestore: firestore,
        collection: collection,
      );
      var doc = await coll.getDoc('dummy');
      expect(doc.exists, isFalse);
      var id = 'my_key';
      doc = _Test()..title.v = 'doc title';
      await coll.setDoc(id, doc);
      var readDoc = await coll.getDoc(id);
      expect(readDoc, doc);
      var docAdded = _Test()..title.v = 'doc title added';
      var addedDocId = await coll.addDoc(docAdded);
      readDoc = await coll.getDoc(addedDocId);
      expect(readDoc, docAdded);

      await coll.deleteDoc(addedDocId);
      readDoc = await coll.getDoc(addedDocId);
      expect(readDoc.exists, isFalse);
    });
  });
}
