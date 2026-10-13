import 'package:tekaly_firestore_synced/synced_firestore_sdb.dart';
import 'package:tekaly_firestore_synced/synced_firestore_trigger.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  cvAddConstructors([DbTest.new]);
  late Firestore firestore;

  setUp(() {
    firestore = newFirestoreMemory();
  });

  SyncedFsCollection<DbTest> newCollection({
    bool collectionChanges = true,
    bool tombstoneKeepsData = false,
  }) => SyncedFsCollection(
    firestore: firestore,
    collection: testCollectionReference,
    options: SyncedFsCollectionOptions(
      collectionChanges: collectionChanges,
      tombstoneKeepsData: tombstoneKeepsData,
    ),
  );

  Future<Model?> rawDoc(String id) async =>
      (await firestore.doc('test/$id').get()).dataOrNull;

  group('transaction', () {
    test('read, decide, write', () async {
      var coll = newCollection(collectionChanges: false);
      var result = await coll.runTransaction((txn) async {
        var doc = await txn.getDoc('k1');
        expect(doc.exists, isFalse);
        expect(doc.isAlive, isFalse);
        expect(doc.isDeleted, isFalse);
        expect(doc.changeId, isNull);
        expect(txn.lastChangeId, 0);
        var id1 = txn.setDoc('k1', DbTest()..title.v = 't1');
        var id2 = txn.setDoc('k2', DbTest()..title.v = 't2');
        expect(txn.lastChangeId, 2);
        // Firestore: no read after a write.
        expect(() => txn.getDoc('k3'), throwsStateError);
        return [id1, id2];
      });
      expect(result, [1, 2]);
      expect(await coll.getLastChangeId(), 2);
      expect((await coll.getChangeList()).list, hasLength(2));

      await coll.runTransaction((txn) async {
        var doc = await txn.getDoc('k1');
        expect(doc.isAlive, isTrue);
        expect(doc.changeId, 1);
        expect(doc.doc.title.v, 't1');
        expect(txn.meta.lastChangeId.v, 2);
        expect(txn.deleteDoc('k1'), 3);
      });
      await coll.runTransaction((txn) async {
        var doc = await txn.getDoc('k1');
        expect(doc.exists, isTrue);
        expect(doc.isDeleted, isTrue);
        expect(doc.isAlive, isFalse);
        expect(doc.changeId, 3);
      });
      expect((await coll.getDoc('k1')).exists, isFalse);
    });

    test('nothing written, meta untouched', () async {
      var coll = newCollection();
      await coll.runTransaction((txn) => txn.getDoc('k1'));
      expect(await coll.getMetaInfo(), isNull);
    });

    test('a tombstone drops the content by default', () async {
      var coll = newCollection();
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.deleteDoc('k1');
      var tombstone = (await rawDoc('k1'))!;
      expect(tombstone.keys, [syncedFieldKey]);
      expect(tombstone.syncedIsDeleted, isTrue);
      expect(tombstone.syncedChangeIdOrNull, 2);
      // Deleting a tombstone again allocates nothing.
      await coll.deleteDoc('k1');
      await coll.deleteDoc('missing');
      expect(await coll.getLastChangeId(), 2);
    });

    test('tombstoneKeepsData', () async {
      var coll = newCollection(tombstoneKeepsData: true);
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.deleteDoc('k1');
      var tombstone = (await rawDoc('k1'))!;
      expect(tombstone['title'], 't1');
      expect(tombstone.syncedIsDeleted, isTrue);
    });
  });

  group('collection changes', () {
    test('no change log, changes from the collection', () async {
      var coll = newCollection();
      expect(coll.source.supportsFullChangeList, isTrue);
      expect(coll.source.collectionChanges, isTrue);
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await coll.setDoc('k2', DbTest()..title.v = 't2');
      await coll.setDoc('k1', DbTest()..title.v = 't1.1');
      await coll.deleteDoc('k2');
      expect(
        (await firestore
                .collection('test$syncedFsChangesCollectionSuffix')
                .get())
            .docs,
        isEmpty,
      );

      var changes = await coll.getChangeList();
      expect(changes.lastChangeId, 4);
      // One entry per document, at its current modification number.
      expect(changes.list.map((change) => change.changeId.v), [3, 4]);
      var k1 = changes.list.first;
      expect(k1.docId.v, 'k1');
      expect(k1.deleted.v, isFalse);
      expect(k1.data.v, {'title': 't1.1'});
      expect(k1.timestamp.v, isNotNull);
      var k2 = changes.list.last;
      expect(k2.docId.v, 'k2');
      expect(k2.deleted.v, isTrue);
      expect(k2.data.v, isNull);

      changes = await coll.getChangeList(afterChangeId: 3, limit: 10);
      expect(changes.list.map((change) => change.docId.v), ['k2']);
      changes = await coll.getChangeList(afterChangeId: 0, limit: 1);
      expect(changes.list.map((change) => change.docId.v), ['k1']);

      // The same source standalone.
      var source = SyncedFsFirestoreSource(
        firestore: firestore,
        path: 'test',
        collectionChanges: true,
      );
      expect(
        (await source.getChangeList()).list.map((change) => change.docId.v),
        ['k1', 'k2'],
      );
      // The change log source sees nothing.
      expect(
        (await SyncedFsFirestoreSource(
          firestore: firestore,
          path: 'test',
        ).getChangeList()).list,
        isEmpty,
      );
      expect(
        SyncedFsFirestoreSource(
          firestore: firestore,
          path: 'test',
        ).supportsFullChangeList,
        isFalse,
      );
    });
  });

  group('purge tombstones', () {
    test('old tombstones, minIncrementalChangeId', () async {
      var coll = newCollection();
      for (var i = 1; i <= 5; i++) {
        await coll.setDoc('k$i', DbTest()..title.v = 't$i');
      }
      await coll.deleteDoc('k1'); // 6
      await coll.deleteDoc('k3'); // 7
      await coll.deleteDoc('k4'); // 8
      var rebuilder = SyncedFsChangeLogRebuilder(
        firestore: firestore,
        path: 'test',
      );
      var past = DateTime.now().subtract(const Duration(days: 1));
      expect(await rebuilder.purgeTombstones(before: past), 0);
      expect((await coll.getMetaInfo())!.minIncrementalChangeId.v, isNull);

      var future = DateTime.now().add(const Duration(minutes: 1));
      expect(await rebuilder.purgeTombstones(before: future, limit: 2), 2);
      expect(await rawDoc('k1'), isNull);
      expect(await rawDoc('k3'), isNull);
      expect((await rawDoc('k4'))!.syncedIsDeleted, isTrue);
      expect((await coll.getMetaInfo())!.minIncrementalChangeId.v, 7);

      expect(await rebuilder.purgeTombstones(before: future), 1);
      expect(await rawDoc('k4'), isNull);
      expect((await coll.getMetaInfo())!.minIncrementalChangeId.v, 8);
      // The alive documents stay.
      expect(
        (await coll.getChangeList()).list.map((change) => change.docId.v),
        ['k2', 'k5'],
      );
    });
  });

  group('sdb mirror', () {
    test('paged full sync, deletions, purge, stale mirror', () async {
      var coll = newCollection();
      var factory = newSdbFactoryMemory();
      Future<(SdbDatabase, SyncedFsSdbSynchronizer)> openMirror(
        String name,
      ) async {
        var db = await factory.openDatabase(
          name,
          options: SdbOpenDatabaseOptions(version: 1, schema: itemSchema),
        );
        addTearDown(db.close);
        return (
          db,
          SyncedFsSdbSynchronizer(
            source: coll.source,
            database: db,
            store: itemStoreRef,
            stepLimit: 2,
          ),
        );
      }

      await coll.runTransaction((txn) async {
        for (var i = 1; i <= 5; i++) {
          txn.setDoc('k$i', DbTest()..title.v = 't$i');
        }
      });
      await coll.deleteDoc('k5');

      var (db, mirror) = await openMirror('mirror.db');
      // A stale local record, removed by the full sync.
      await itemStoreRef.record('ghost').put(db, {'title': 'ghost'});
      var result = await mirror.sync();
      expect(result.fullSync, isTrue);
      expect(result.appliedCount, 4);
      expect(result.lastChangeId, 6);
      expect((await storeContent(db)).keys, ['k1', 'k2', 'k3', 'k4']);
      expect((await storeContent(db))['k1'], {'title': 't1'});

      // Incremental: an update and two deletions.
      await coll.runTransaction((txn) async {
        var k1 = await txn.getDoc('k1');
        txn.setDoc('k1', k1.doc..title.v = 't1.1');
        txn.deleteDoc('k2');
        txn.deleteDoc('k3');
      });
      // A mirror left behind before the purge.
      var (staleDb, stale) = await openMirror('stale.db');
      await stale.sync();
      await coll.setDoc('k6', DbTest()..title.v = 't6');

      result = await mirror.sync();
      expect(result.fullSync, isFalse);
      expect(result.appliedCount, 2);
      expect(result.deletedCount, 2);
      expect((await storeContent(db)).keys, ['k1', 'k4', 'k6']);

      // Purge: the tombstones of k5 (6), k2 (8) and k3 (9) go, a mirror
      // synchronized below 9 may have missed one of them.
      var rebuilder = SyncedFsChangeLogRebuilder(
        firestore: firestore,
        path: 'test',
      );
      expect(
        await rebuilder.purgeTombstones(
          before: DateTime.now().add(const Duration(minutes: 1)),
        ),
        3,
      );
      expect((await coll.getMetaInfo())!.minIncrementalChangeId.v, 9);
      // Up to date mirror: incremental, nothing new.
      result = await mirror.sync();
      expect(result.fullSync, isFalse);
      expect(result.isEmpty, isTrue);

      // A mirror synchronized before change 9: full, paged.
      var (oldDb, old) = await openMirror('old.db');
      await old.sync();
      await syncedFsSdbMetaStoreRef
          .record(itemStoreRef.name)
          .put(oldDb, (await old.getSyncMetaInfo())!..lastChangeId.v = 7);
      await itemStoreRef.record('k2').put(oldDb, {'title': 'deleted long ago'});
      result = await old.sync();
      expect(result.fullSync, isTrue);
      expect(result.lastChangeId, 10);
      expect((await storeContent(oldDb)).keys, ['k1', 'k4', 'k6']);
      expect((await storeContent(oldDb))['k1'], {'title': 't1.1'});

      // The stale one (synchronized up to 9) catches up incrementally.
      result = await stale.sync();
      expect(result.fullSync, isFalse);
      expect((await storeContent(staleDb)).keys, ['k1', 'k4', 'k6']);
    });

    test('purged newest tombstone, one full sync only', () async {
      var coll = newCollection();
      await coll.setDoc('k1', DbTest()..title.v = 't1'); // 1
      await coll.setDoc('k2', DbTest()..title.v = 't2'); // 2
      await coll.deleteDoc('k2'); // 3, the newest change
      var rebuilder = SyncedFsChangeLogRebuilder(
        firestore: firestore,
        path: 'test',
      );
      expect(
        await rebuilder.purgeTombstones(
          before: DateTime.now().add(const Duration(minutes: 1)),
        ),
        1,
      );
      expect((await coll.getMetaInfo())!.minIncrementalChangeId.v, 3);
      var db = await newSdbFactoryMemory().openDatabase(
        'purged.db',
        options: SdbOpenDatabaseOptions(version: 1, schema: itemSchema),
      );
      addTearDown(db.close);
      var mirror = SyncedFsSdbSynchronizer(
        source: coll.source,
        database: db,
        store: itemStoreRef,
      );
      var result = await mirror.sync();
      expect(result.fullSync, isTrue);
      expect(result.lastChangeId, 3);
      expect((await storeContent(db)).keys, ['k1']);
      for (var i = 0; i < 2; i++) {
        result = await mirror.sync();
        expect(result.fullSync, isFalse);
        expect(result.lastChangeId, 3);
      }
    });
  });
}
