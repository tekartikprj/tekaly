import 'package:tekaly_firestore_synced/synced_firestore_trigger.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  cvAddConstructors([DbTest.new]);
  group('synced_fs_rebuild', () {
    late Firestore firestore;
    late SyncedFsCollection<DbTest> coll;
    late SyncedFsCollection<DbTest> noLogColl;
    late SyncedFsChangeLogRebuilder rebuilder;

    setUp(() {
      firestore = newFirestoreMemory();
      coll = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
      );
      noLogColl = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
        options: const SyncedFsCollectionOptions(writeChangeLog: false),
      );
      rebuilder = SyncedFsChangeLogRebuilder(
        firestore: firestore,
        path: 'test',
      );
    });

    test('rebuild from scratch', () async {
      await noLogColl.setDoc('k1', DbTest()..title.v = 't1');
      await noLogColl.setDoc('k2', DbTest()..title.v = 't2');
      await noLogColl.deleteDoc('k1');
      expect((await coll.getChangeList()).isEmpty, isTrue);

      var result = await rebuilder.rebuild();
      expect(result.scannedCount, 2);
      expect(result.addedCount, 2);
      expect(result.complete, isTrue);

      var changes = await coll.getChangeList();
      expect(changes.length, 2);
      expect(changes.list.map((e) => e.docId.v), ['k2', 'k1']);
      expect(changes.list.map((e) => e.changeId.v), [2, 3]);
      expect(changes.list.map((e) => e.deleted.v), [false, true]);
      expect(changes.list.first.origin.v, SyncedFsChangeOrigin.rebuild);
      expect(changes.list.first.data.v, {'title': 't2'});

      /// The tombstone of k1 carries no data.
      expect(changes.list.last.data.v, isNull);

      /// Idempotent, a second rebuild adds nothing.
      result = await rebuilder.rebuild();
      expect(result.addedCount, 0);
      expect((await coll.getChangeList()).length, 2);
    });

    test('rebuild since a modification number', () async {
      await noLogColl.setDoc('k1', DbTest()..title.v = 't1');
      await noLogColl.setDoc('k2', DbTest()..title.v = 't2');
      await noLogColl.setDoc('k3', DbTest()..title.v = 't3');

      var result = await rebuilder.rebuild(sinceChangeId: 1);
      expect(result.scannedCount, 2);
      expect(result.addedCount, 2);
      expect((await coll.getChangeList()).list.map((e) => e.docId.v), [
        'k2',
        'k3',
      ]);
    });

    test('rebuild resumes from the meta watermark', () async {
      await noLogColl.setDoc('k1', DbTest()..title.v = 't1');
      var result = await rebuilder.rebuild();
      expect(result.addedCount, 1);
      expect((await coll.getMetaInfo())!.changeLogChangeId.v, 1);

      await noLogColl.setDoc('k2', DbTest()..title.v = 't2');
      result = await rebuilder.rebuild();
      expect(result.scannedCount, 1);
      expect(result.addedCount, 1);
      expect((await coll.getMetaInfo())!.changeLogChangeId.v, 2);
    });

    test('rebuild with a limit is resumable', () async {
      for (var i = 0; i < 5; i++) {
        await noLogColl.setDoc('k$i', DbTest()..title.v = 't$i');
      }
      var result = await rebuilder.rebuild(limit: 2, stepLimit: 2);
      expect(result.scannedCount, 2);
      expect(result.addedCount, 2);
      expect(result.complete, isFalse);
      expect(result.lastChangeId, 2);

      /// Not complete, the watermark was not moved.
      expect((await coll.getMetaInfo())?.changeLogChangeId.v, isNull);

      result = await rebuilder.rebuild(sinceChangeId: result.lastChangeId);
      expect(result.addedCount, 3);
      expect(result.complete, isTrue);
      expect((await coll.getChangeList()).length, 5);
    });

    test('stamp missing modification numbers', () async {
      /// Documents written with no synced information at all: invisible to a
      /// rebuild, which orders by modification number.
      await firestore.doc('test/k1').set({'title': 't1'});
      await firestore.doc('test/k2').set({'title': 't2'});
      expect((await rebuilder.rebuild()).scannedCount, 0);

      var result = await rebuilder.stampMissingChangeIds();
      expect(result.scannedCount, 2);
      expect(result.stampedCount, 2);
      expect(result.addedCount, 2);

      var changes = await coll.getChangeList();
      expect(changes.length, 2);
      expect(changes.list.map((e) => e.docId.v), ['k1', 'k2']);
      expect(await coll.getLastChangeId(), 2);

      /// Idempotent.
      result = await rebuilder.stampMissingChangeIds();
      expect(result.scannedCount, 2);
      expect(result.stampedCount, 0);
    });

    test('reconcile', () async {
      await noLogColl.setDoc('k1', DbTest()..title.v = 't1');
      await noLogColl.setDoc('k2', DbTest()..title.v = 't2');

      var result = await rebuilder.reconcile();
      expect(result.scannedCount, 2);
      expect(result.addedCount, 2);
      expect((await coll.getChangeList()).length, 2);
      expect(
        (await coll.getChangeList()).list.first.origin.v,
        SyncedFsChangeOrigin.reconcile,
      );
      expect((await coll.getMetaInfo())!.lastReconcileTimestamp.v, isNotNull);

      /// Idempotent, everything is already there.
      result = await rebuilder.reconcile(sinceTimestamp: null);
      expect(result.addedCount, 0);
    });

    test('truncate and version bump', () async {
      for (var i = 0; i < 4; i++) {
        await coll.setDoc('k$i', DbTest()..title.v = 't$i');
      }
      expect((await coll.getChangeList()).length, 4);

      expect(await rebuilder.truncateChangeLog(beforeChangeId: 3), 2);
      expect((await coll.getChangeList()).length, 2);
      expect((await coll.getMetaInfo())!.minIncrementalChangeId.v, 3);

      expect(await rebuilder.bumpVersion(), 2);
      expect((await coll.getMetaInfo())!.version.v, 2);
    });
  });
}
