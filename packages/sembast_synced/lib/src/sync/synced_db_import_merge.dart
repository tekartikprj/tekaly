import 'package:collection/collection.dart';
import 'package:sembast/utils/database_utils.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

/// Import [sourceDatabase], an export opened in memory, into the synced stores
/// of [db] and set its sync meta from [exportMeta] (the fetched export meta).
///
/// Like the sdb import:
/// * only the synced stores of [db] are changed: its local (`local_*`,
///   `*_local`) and system stores (meta, sync records) are never touched and
///   the ones of the export are ignored;
/// * a synced store missing from the export is emptied (an export is a
///   snapshot that never lists an empty store);
/// * changes are not tracked (no sync record is created) and the existing
///   sync records are kept. A record with a pending local change gets the
///   exported value (or is removed when not exported) and keeps its dirty
///   sync record: the next sync up re-applies a pending local delete, a
///   pending local edit or creation is replaced by the export snapshot.
Future<void> syncedDbImportSourceDatabase(
  SyncedDb db, {
  required Database sourceDatabase,
  required SyncedDbExportMeta exportMeta,
}) async {
  var sourceStoreNames = getNonEmptyStoreNames(
    sourceDatabase,
  ).where(db.shouldSyncStore).toSet();
  var database = await db.database;
  await db.syncTransaction((txn) async {
    var storeNames = {
      ...getNonEmptyStoreNames(database).where(db.shouldSyncStore),
      ...sourceStoreNames,
    };
    for (var storeName in storeNames) {
      var store = StoreRef<Object, Object>(storeName);
      var source = <Object, Object>{
        if (sourceStoreNames.contains(storeName))
          for (var record in await store.find(sourceDatabase))
            record.key: record.value,
      };
      for (var record in await store.find(txn)) {
        var value = source.remove(record.key);
        if (value == null) {
          await store.record(record.key).delete(txn);
        } else if (!const DeepCollectionEquality().equals(
          value,
          record.value,
        )) {
          await store.record(record.key).put(txn, value);
        }
      }
      for (var entry in source.entries) {
        await store.record(entry.key).put(txn, entry.value);
      }
    }
    await (db.dbSyncMetaInfoRef.cv()
          ..lastChangeId.setValue(exportMeta.lastChangeId.v)
          ..lastTimestamp.setValue(
            SyncedDbTimestamp.tryParse(exportMeta.lastTimestamp.v),
          )
          ..sourceVersion.setValue(exportMeta.sourceVersion.v))
        .put(txn);
  });
}

/// Stores of a legacy export of [db] ([database] is its database): the synced
/// stores and the sync meta store (importers of the legacy format before the
/// synced import read their sync meta from it), never the sync records nor
/// the local stores.
List<String> syncedDbLegacyExportStoreNames(SyncedDb db, Database database) =>
    getNonEmptyStoreNames(database)
        .where(
          (name) =>
              name == db.dbSyncMetaStoreRef.name || db.shouldSyncStore(name),
        )
        .toList();
