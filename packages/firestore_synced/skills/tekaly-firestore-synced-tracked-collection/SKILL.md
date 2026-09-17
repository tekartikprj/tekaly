---
name: tekaly-firestore-synced-tracked-collection
description: >-
  Use when making a firestore collection incrementally consumable with
  tekaly_firestore_synced: writing through SyncedFsCollection, feeding the
  change log from a cloud function trigger (SyncedFsCollectionTrigger) and
  rebuilding or reconciling it (SyncedFsChangeLogRebuilder).
---

# Tracked firestore collection (tekaly_firestore_synced)

Every document of a tracked collection `item` carries a `synced` map
(`changeId`, `deleted`, `timestamp`); each modification appends an immutable
entry to `item_changes` (id = zero padded change id) and bumps
`item_meta/info.lastChangeId`. Consumers resume from a change id with one read
per page. Deletions are soft (tombstones).

## Guidelines

* Client/common code imports
  `package:tekaly_firestore_synced/synced_firestore.dart`; server code
  (cloud functions, scripts) imports `synced_firestore_trigger.dart`.
* Write through `SyncedFsCollection(firestore:, collection:
  CvCollectionReference<T>('item'))`: `setDoc`, `addDoc`, `deleteDoc`
  (tombstone), `getDoc`. Each write allocates the next change id, stamps the
  document and appends the change log entry in one transaction. Register the
  cv document constructor (`cvAddConstructors([DbItem.new])`) first.
* Never hard delete a tracked document; a hard deletion is only healed by the
  trigger, which writes a tombstone entry.
* Options: `SyncedFsCollectionOptions(writeChangeLog: false)` when the
  trigger feeds the log, `changeLogIncludesData: false` to keep the log small
  (consumers then fetch snapshots).
* For writes going around the helper, deploy an `onWrite` trigger on
  `item/{docId}` calling `SyncedFsCollectionTrigger(firestore:, path:
  'item').onDocumentSnapshotWrite(before:, after:)` (or
  `onDocumentWrite(docId:, before:, after:)`); it is idempotent.
* Schedule `SyncedFsChangeLogRebuilder(firestore:, path:).reconcile(since:)`
  (cheap, walks recent updates) and run `stampMissingChangeIds()` once when
  enabling the helpers on an existing collection; `rebuild(sinceChangeId:)`
  recovers a compacted log on demand. Both take a `limit` and report
  `complete: false` when they stop on it: resume from the returned
  `lastChangeId`.
* `truncateChangeLog(beforeChangeId:)` forces consumers below to resync;
  `bumpVersion()` forces every consumer to resync.
* Consumers read through `SyncedFsFirestoreSource(firestore:, path:)`
  (`getChangeList(afterChangeId:)`, `getSnapshot()`); `coll.source` gives the
  same source. Use `tekaly-firestore-synced-sdb-mirror` for a local sdb copy.

## Examples

### Writing

```dart
import 'package:tekaly_firestore_synced/synced_firestore.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

class DbItem extends CvFirestoreDocumentBase {
  final title = CvField<String>('title');
  @override
  CvFields get fields => [title];
}

Future<void> write(Firestore firestore) async {
  cvAddConstructors([DbItem.new]);
  var coll = SyncedFsCollection(
    firestore: firestore,
    collection: CvCollectionReference<DbItem>('item'),
  );
  await coll.setDoc('k1', DbItem()..title.v = 'hello');
  var id = await coll.addDoc(DbItem()..title.v = 'added');
  await coll.deleteDoc(id); // tombstone
  print((await coll.getDoc('k1'))?.title.v);
}
```

### Cloud function trigger and scheduled reconciliation

```dart
import 'package:tekaly_firestore_synced/synced_firestore_trigger.dart';

Future<void> onItemWrite(
  Firestore firestore,
  DocumentSnapshot? before,
  DocumentSnapshot? after,
) async {
  var trigger = SyncedFsCollectionTrigger(firestore: firestore, path: 'item');
  await trigger.onDocumentSnapshotWrite(before: before, after: after);
}

Future<void> hourlyReconcile(Firestore firestore) async {
  var rebuilder = SyncedFsChangeLogRebuilder(firestore: firestore, path: 'item');
  var result = await rebuilder.reconcile(since: const Duration(hours: 1));
  print('${result.addedCount} entry(ies) added, complete: ${result.complete}');
}
```
