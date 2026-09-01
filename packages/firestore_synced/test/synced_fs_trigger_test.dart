import 'package:tekaly_firestore_synced/synced_firestore_trigger.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  cvAddConstructors([DbTest.new]);
  group('synced_fs_trigger', () {
    late Firestore firestore;
    late SyncedFsCollection<DbTest> coll;
    late SyncedFsCollectionTrigger trigger;

    setUp(() {
      firestore = newFirestoreMemory();
      coll = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
      );
      trigger = SyncedFsCollectionTrigger(firestore: firestore, path: 'test');
    });

    Future<Model?> rawMap(String id) async =>
        (await firestore.doc('test/$id').get()).dataOrNull;

    test('untracked write is healed', () async {
      /// A write not going through the synced helpers, no modification number.
      await firestore.doc('test/k1').set({'title': 't1'});
      expect((await rawMap('k1'))!.syncedChangeIdOrNull, isNull);

      var change = await trigger.onDocumentWrite(
        docId: 'k1',
        after: await rawMap('k1'),
      );
      expect(change!.changeId.v, 1);
      expect(change.docId.v, 'k1');
      expect(change.origin.v, SyncedFsChangeOrigin.trigger);
      expect(change.data.v, {'title': 't1'});

      /// The document itself is stamped.
      expect((await rawMap('k1'))!.syncedChangeIdOrNull, 1);
      expect(await coll.getLastChangeId(), 1);
      expect((await coll.getChangeList()).length, 1);
    });

    test('already tracked write is a no op', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      var after = await rawMap('k1');

      /// The entry was written in the same transaction, the trigger has
      /// nothing to add (at least once delivery, idempotency).
      expect(await trigger.onDocumentWrite(docId: 'k1', after: after), isNull);
      expect(
        await trigger.onDocumentWrite(docId: 'k1', before: after, after: after),
        isNull,
      );
      expect((await coll.getChangeList()).length, 1);
      expect(await coll.getLastChangeId(), 1);
    });

    test('write without the change log', () async {
      var noLog = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
        options: const SyncedFsCollectionOptions(writeChangeLog: false),
      );
      await noLog.setDoc('k1', DbTest()..title.v = 't1');
      expect((await noLog.getChangeList()).isEmpty, isTrue);

      var change = await trigger.onDocumentWrite(
        docId: 'k1',
        after: await rawMap('k1'),
      );
      expect(change!.changeId.v, 1);
      expect(change.data.v, {'title': 't1'});
      expect((await noLog.getChangeList()).length, 1);

      /// Running the trigger twice is a no op.
      expect(
        await trigger.onDocumentWrite(docId: 'k1', after: await rawMap('k1')),
        isNull,
      );
      expect((await noLog.getChangeList()).length, 1);
    });

    test('content changed without a new modification number', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      var before = await rawMap('k1');

      /// Someone updated the content keeping the synced information.
      await firestore.doc('test/k1').set({...before!, 'title': 't1.1'});
      var after = await rawMap('k1');
      expect(after!.syncedChangeIdOrNull, 1);

      var change = await trigger.onDocumentWrite(
        docId: 'k1',
        before: before,
        after: after,
      );
      expect(change!.changeId.v, 2);
      expect(change.data.v, {'title': 't1.1'});
      expect((await rawMap('k1'))!.syncedChangeIdOrNull, 2);
    });

    test('hard deletion', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await firestore.doc('test/k1').delete();

      var change = await trigger.onDocumentWrite(docId: 'k1');
      expect(change!.changeId.v, 2);
      expect(change.deleted.v, isTrue);
      expect(change.data.v, isNull);

      var changes = await coll.getChangeList(afterChangeId: 1);
      expect(changes.list.single.deleted.v, isTrue);
    });

    test('from snapshots', () async {
      await firestore.doc('test/k1').set({'title': 't1'});
      var after = await firestore.doc('test/k1').get();
      var change = await trigger.onDocumentSnapshotWrite(after: after);
      expect(change!.changeId.v, 1);
      expect(change.updateTime.v, isNotNull);
      expect(change.docId.v, 'k1');
    });
  });
}
