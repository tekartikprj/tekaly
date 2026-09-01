import 'package:tekaly_firestore_synced/synced_firestore_sdb.dart';
import 'package:tekaly_firestore_synced/synced_firestore_trigger.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart' as fs;
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  fs.cvAddConstructors([DbTest.new]);
  group('synced_fs_sdb', () {
    late fs.Firestore firestore;
    late SyncedFsCollection<DbTest> coll;
    late SdbDatabase db;
    late SyncedFsSdbSynchronizer synchronizer;

    setUp(() async {
      firestore = newFirestoreMemory();
      coll = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
      );
      db = await newSdbFactoryMemory().openDatabase(
        'test.db',
        options: SdbOpenDatabaseOptions(version: 1, schema: itemSchema),
      );
      synchronizer = SyncedFsSdbSynchronizer(
        source: coll.source,
        database: db,
        store: itemStoreRef,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('empty', () async {
      var result = await synchronizer.sync();
      expect(result.fullSync, isTrue);
      expect(result.isEmpty, isTrue);
      expect(result.lastChangeId, 0);
      expect(await storeContent(db), isEmpty);

      /// Recorded, the next one is incremental.
      result = await synchronizer.sync();
      expect(result.fullSync, isFalse);
      expect(await synchronizer.getLastChangeId(), 0);
    });

    test('full then incremental', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.setDoc('k2', DbTest()..title.v = 't2');

      var result = await synchronizer.sync();
      expect(result.fullSync, isTrue);
      expect(result.appliedCount, 2);
      expect(result.lastChangeId, 2);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
        'k2': {'title': 't2'},
      });

      await coll.setDoc('k3', DbTest()..title.v = 't3');
      await coll.setDoc('k1', DbTest()..title.v = 't1.1');
      result = await synchronizer.sync();
      expect(result.fullSync, isFalse);
      expect(result.appliedCount, 2);
      expect(result.lastChangeId, 4);
      expect(await storeContent(db), {
        'k1': {'title': 't1.1'},
        'k2': {'title': 't2'},
        'k3': {'title': 't3'},
      });

      /// Nothing new.
      result = await synchronizer.sync();
      expect(result.isEmpty, isTrue);
      expect(result.lastChangeId, 4);
    });

    test('deletion', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.setDoc('k2', DbTest()..title.v = 't2');
      await synchronizer.sync();

      await coll.deleteDoc('k1');
      var result = await synchronizer.sync();
      expect(result.deletedCount, 1);
      expect(await storeContent(db), {
        'k2': {'title': 't2'},
      });
    });

    test('replaying a change is idempotent', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();

      /// Force the replay of every change from the beginning.
      await synchronizer.sync();
      var changes = await coll.getChangeList();
      expect(changes.length, 1);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
      });
    });

    test('timestamp conversion', () async {
      await coll.setMap('k1', {'title': 't1', 'time': fs.Timestamp(1000, 2)});
      await synchronizer.sync();
      expect(await storeContent(db), {
        'k1': {'title': 't1', 'time': SdbTimestamp(1000, 2)},
      });
    });

    test('version bump forces a full sync', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();

      /// A local record the source does not have any more.
      await itemStoreRef.record('gone').put(db, {'title': 'stale'});

      var rebuilder = SyncedFsChangeLogRebuilder(
        firestore: firestore,
        path: 'test',
      );
      await rebuilder.bumpVersion();
      var result = await synchronizer.sync();
      expect(result.fullSync, isTrue);
      expect(result.deletedCount, 1);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
      });
      expect((await synchronizer.getSyncMetaInfo())!.sourceVersion.v, 2);
    });

    test('change log truncation forces a full sync', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();
      await coll.setDoc('k2', DbTest()..title.v = 't2');
      await coll.setDoc('k3', DbTest()..title.v = 't3');

      var rebuilder = SyncedFsChangeLogRebuilder(
        firestore: firestore,
        path: 'test',
      );
      await rebuilder.truncateChangeLog(beforeChangeId: 3);
      var result = await synchronizer.sync();
      expect(result.fullSync, isTrue);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
        'k2': {'title': 't2'},
        'k3': {'title': 't3'},
      });
    });

    test('change log without data fetches the snapshot', () async {
      var noData = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
        options: const SyncedFsCollectionOptions(changeLogIncludesData: false),
      );
      await noData.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();
      await noData.setDoc('k2', DbTest()..title.v = 't2');

      var result = await synchronizer.sync();
      expect(result.fullSync, isFalse);
      expect(result.appliedCount, 1);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
        'k2': {'title': 't2'},
      });
    });

    test('another source forces a full sync', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();
      expect((await synchronizer.getSyncMetaInfo())!.source.v, 'test');

      var other = SyncedFsCollection(
        firestore: firestore,
        collection: fs.CvCollectionReference<DbTest>('other'),
      );
      await other.setDoc('o1', DbTest()..title.v = 'o1');
      var otherSynchronizer = SyncedFsSdbSynchronizer(
        source: other.source,
        database: db,
        store: itemStoreRef,
      );
      var result = await otherSynchronizer.sync();
      expect(result.fullSync, isTrue);
      expect(await storeContent(db), {
        'o1': {'title': 'o1'},
      });
    });

    test('dead letter queue', () async {
      /// A document reference cannot be stored in sdb.
      await coll.setMap('bad', {
        'title': 'bad',
        'ref': firestore.doc('other/x'),
      });
      await coll.setDoc('k1', DbTest()..title.v = 't1');

      var result = await synchronizer.sync();
      expect(result.failedCount, 1);
      expect(result.appliedCount, 1);

      /// One bad document does not block the rest, nor the modification
      /// number the next synchronization resumes from.
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
      });
      expect(result.lastChangeId, 2);

      var deadLetters = await synchronizer.getDeadLetters();
      expect(deadLetters.length, 1);
      var deadLetter = deadLetters.single;
      expect(deadLetter.docId.v, 'bad');
      expect(deadLetter.store.v, 'item');
      expect(deadLetter.retryCount.v, 0);
      expect(deadLetter.error.v, contains('not supported in sdb'));

      /// Retrying while the document is still bad keeps it queued.
      result = await synchronizer.retryDeadLetters();
      expect(result.failedCount, 1);
      expect((await synchronizer.getDeadLetters()).single.retryCount.v, 1);

      /// Fix the document, the dead letter applies and is dropped.
      await coll.setMap('bad', {'title': 'fixed'});
      result = await synchronizer.retryDeadLetters();
      expect(result.appliedCount, 1);
      expect(result.failedCount, 0);
      expect(await synchronizer.getDeadLetters(), isEmpty);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
        'bad': {'title': 'fixed'},
      });
    });

    test('dead letter of a deleted document', () async {
      await coll.setMap('bad', {'ref': firestore.doc('other/x')});
      await synchronizer.sync();
      expect((await synchronizer.getDeadLetters()).length, 1);

      await coll.deleteDoc('bad');
      var result = await synchronizer.retryDeadLetters();
      expect(result.deletedCount, 1);
      expect(await synchronizer.getDeadLetters(), isEmpty);
      expect(await storeContent(db), isEmpty);
    });

    test('reset', () async {
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();
      await synchronizer.reset();
      expect(await storeContent(db), isEmpty);
      expect(await synchronizer.getSyncMetaInfo(), isNull);
      var result = await synchronizer.sync();
      expect(result.fullSync, isTrue);
      expect(result.appliedCount, 1);
    });
  });
}
