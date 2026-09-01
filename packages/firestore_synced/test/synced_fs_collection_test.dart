import 'package:tekaly_firestore_synced/synced_firestore.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  cvAddConstructors([DbTest.new]);
  group('synced_fs_collection', () {
    late Firestore firestore;
    late SyncedFsCollection<DbTest> coll;

    setUp(() {
      firestore = newFirestoreMemory();
      coll = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
      );
    });

    test('get/put/add/delete', () async {
      var doc = await coll.getDoc('dummy');
      expect(doc.exists, isFalse);
      var id = 'my_key';
      doc = DbTest()..title.v = 'doc title';
      await coll.setDoc(id, doc);
      var readDoc = await coll.getDoc(id);
      expect(readDoc, doc);
      var docAdded = DbTest()..title.v = 'doc title added';
      var addedDocId = await coll.addDoc(docAdded);
      readDoc = await coll.getDoc(addedDocId);
      expect(readDoc, docAdded);

      await coll.deleteDoc(addedDocId);
      readDoc = await coll.getDoc(addedDocId);
      expect(readDoc.exists, isFalse);
    });

    test('modification number', () async {
      expect(await coll.getLastChangeId(), 0);
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      expect(await coll.getLastChangeId(), 1);
      var info = await rawSyncedInfo(firestore, 'test/k1');
      expect(info!.changeId.v, 1);
      expect(info.modificationNumber, 1);
      expect(info.deleted.v, isFalse);
      expect(info.timestamp.v, isNotNull);

      await coll.setDoc('k2', DbTest()..title.v = 't2');
      expect((await rawSyncedInfo(firestore, 'test/k2'))!.changeId.v, 2);
      await coll.setDoc('k1', DbTest()..title.v = 't1.1');
      expect((await rawSyncedInfo(firestore, 'test/k1'))!.changeId.v, 3);
      expect(await coll.getLastChangeId(), 3);
    });

    test('change log', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.setDoc('k2', DbTest()..title.v = 't2');
      var changes = await coll.getChangeList();
      expect(changes.length, 2);
      expect(changes.lastChangeId, 2);
      var first = changes.list.first;
      expect(first.changeId.v, 1);
      expect(first.docId.v, 'k1');
      expect(first.deleted.v, isFalse);
      expect(first.origin.v, SyncedFsChangeOrigin.write);
      expect(first.data.v, {'title': 't1'});
      expect(first.timestamp.v, isNotNull);
      expect(first.id, syncedFsChangeDocId(1));

      /// Everything newer than modification number 1.
      changes = await coll.getChangeList(afterChangeId: 1);
      expect(changes.length, 1);
      expect(changes.list.single.docId.v, 'k2');

      await coll.deleteDoc('k1');
      changes = await coll.getChangeList(afterChangeId: 2);
      expect(changes.length, 1);
      expect(changes.list.single.docId.v, 'k1');
      expect(changes.list.single.deleted.v, isTrue);
      expect(changes.list.single.data.v, isNull);
    });

    test('change log disabled', () async {
      var noLog = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
        options: const SyncedFsCollectionOptions(writeChangeLog: false),
      );
      await noLog.setDoc('k1', DbTest()..title.v = 't1');
      expect((await noLog.getChangeList()).isEmpty, isTrue);
      expect(await noLog.getLastChangeId(), 1);
    });

    test('change log without data', () async {
      var noData = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
        options: const SyncedFsCollectionOptions(changeLogIncludesData: false),
      );
      await noData.setDoc('k1', DbTest()..title.v = 't1');
      var change = (await noData.getChangeList()).list.single;
      expect(change.data.v, isNull);
      expect(change.needsSnapshot, isTrue);
    });

    test('snapshot', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.setDoc('k2', DbTest()..title.v = 't2');
      await coll.deleteDoc('k2');

      var snapshot = await coll.getSnapshot();
      expect(snapshot.docs, {
        'k1': {'title': 't1'},
      });
      expect(snapshot.missing, ['k2']);
      expect(snapshot.lastChangeId, 3);

      /// Full snapshot of some document ids.
      snapshot = await coll.getSnapshot(docIds: ['k2', 'k3']);
      expect(snapshot.docs, isEmpty);
      expect(snapshot.missing, ['k2', 'k3']);

      snapshot = await coll.getSnapshot(docIds: ['k1']);
      expect(snapshot.docs, {
        'k1': {'title': 't1'},
      });
      expect(snapshot.missing, isEmpty);
    });

    test('paged change list', () async {
      for (var i = 0; i < 5; i++) {
        await coll.setDoc('k$i', DbTest()..title.v = 't$i');
      }
      var changes = await coll.getChangeList(limit: 2);
      expect(changes.length, 2);
      expect(changes.lastChangeId, 2);
      changes = await coll.source.getAllChangeList(stepLimit: 2);
      expect(changes.length, 5);
      expect(changes.lastChangeId, 5);
    });
  });
}
