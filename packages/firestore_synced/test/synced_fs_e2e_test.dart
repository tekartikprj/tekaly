import 'package:tekaly_firestore_synced/synced_firestore_sdb.dart';
import 'package:tekaly_firestore_synced/synced_firestore_trigger.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart' as fs;
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

import 'test_common.dart';

void main() {
  fs.cvAddConstructors([DbTest.new]);

  /// The whole design end to end: writes going through the helper, writes
  /// going around it picked up by the trigger, a trigger failure caught by the
  /// scheduled reconciliation, and a local sdb mirror catching up with all of
  /// it.
  test('write, trigger, reconcile, mirror', () async {
    var firestore = newFirestoreMemory();
    var coll = SyncedFsCollection(
      firestore: firestore,
      collection: testCollectionReference,
    );
    var trigger = SyncedFsCollectionTrigger(firestore: firestore, path: 'test');
    var rebuilder = SyncedFsChangeLogRebuilder(
      firestore: firestore,
      path: 'test',
    );
    var db = await newSdbFactoryMemory().openDatabase(
      'e2e.db',
      options: SdbOpenDatabaseOptions(version: 1, schema: itemSchema),
    );
    var synchronizer = SyncedFsSdbSynchronizer(
      source: coll.source,
      database: db,
      store: itemStoreRef,
    );

    try {
      /// 1. A write through the helper, tracked in its own transaction.
      await coll.setDoc('k1', DbTest()..title.v = 't1');
      await synchronizer.sync();
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
      });

      /// 2. A write going around the helper, healed by the cloud function.
      await firestore.doc('test/k2').set({'title': 't2'});
      await trigger.onDocumentSnapshotWrite(
        after: await firestore.doc('test/k2').get(),
      );
      var result = await synchronizer.sync();
      expect(result.fullSync, isFalse);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
        'k2': {'title': 't2'},
      });

      /// 3. A write going around the helper *and* whose trigger never ran.
      await firestore.doc('test/k3').set({'title': 't3'});
      expect((await synchronizer.sync()).isEmpty, isTrue);

      /// The scheduled job stamps it and emits the missing entry.
      expect((await rebuilder.stampMissingChangeIds()).addedCount, 1);
      result = await synchronizer.sync();
      expect(result.appliedCount, 1);
      expect(await storeContent(db), {
        'k1': {'title': 't1'},
        'k2': {'title': 't2'},
        'k3': {'title': 't3'},
      });

      /// 4. A stamped write whose change log entry is missing, caught by the
      /// reconciliation walking recent update times.
      var noLog = SyncedFsCollection(
        firestore: firestore,
        collection: testCollectionReference,
        options: const SyncedFsCollectionOptions(writeChangeLog: false),
      );
      await noLog.setDoc('k1', DbTest()..title.v = 't1.1');
      expect((await synchronizer.sync()).isEmpty, isTrue);
      expect((await rebuilder.reconcile()).addedCount, 1);
      result = await synchronizer.sync();
      expect(result.appliedCount, 1);
      expect(await storeContent(db), {
        'k1': {'title': 't1.1'},
        'k2': {'title': 't2'},
        'k3': {'title': 't3'},
      });

      /// 5. A deletion, propagated as a tombstone.
      await coll.deleteDoc('k2');
      result = await synchronizer.sync();
      expect(result.deletedCount, 1);
      expect(await storeContent(db), {
        'k1': {'title': 't1.1'},
        'k3': {'title': 't3'},
      });

      /// The mirror read exactly what it needed: no full resynchronization
      /// after the first one.
      expect(
        await synchronizer.getLastChangeId(),
        await coll.getLastChangeId(),
      );
    } finally {
      await db.close();
    }
  });
}
