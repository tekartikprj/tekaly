import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' show Firestore;

import 'auto_synced_sdb_firestore.dart';
import 'synced_sdb.dart';

/// A local sdb database synchronized with firestore ([autoSyncedSdb]), or
/// not (tests, previews, a database read once before a sign in): the base
/// of an app database class, which adds its stores and commands.
///
/// An app class extends it (`MyDb(super.db, {super.autoSyncedSdb})`) and
/// opens a synchronized database with [openAutoSynchronized], a local one
/// with `factory.openDatabase`.
class FirestoreSyncedOrLocalSdb {
  /// The open database.
  final SdbDatabase db;

  /// The synchronizer, null for a database that is not synchronized.
  final AutoSynchronizedFirestoreSyncedSdb? autoSyncedSdb;

  /// The database [db], synchronized by [autoSyncedSdb] when given (its
  /// `database`).
  FirestoreSyncedOrLocalSdb(this.db, {this.autoSyncedSdb});

  /// Opens the database [name] of [factory] with [options], synchronized
  /// with [firestore] under the document [rootDocumentPath]: its `database`
  /// and the synchronizer, for the constructor of an app class.
  ///
  /// [options] holds the stores of the app and the sync meta stores
  /// (`syncedSdbMetaSchema.stores`).
  static Future<AutoSynchronizedFirestoreSyncedSdb> openAutoSynchronized({
    required SdbFactory factory,
    required Firestore firestore,
    required String name,
    required String rootDocumentPath,
    required SdbOpenDatabaseOptions options,
  }) => AutoSynchronizedFirestoreSyncedSdb.open(
    options: AutoSynchronizedFirestoreSyncedSdbOptions(
      firestore: firestore,
      databaseFactory: factory,
      dbName: name,
      rootDocumentPath: rootDocumentPath,
      syncedSdbOptions: SyncedSdbOptions(openDatabaseOptions: options),
    ),
  );

  /// True when synchronized with firestore.
  bool get isSynced => autoSyncedSdb != null;

  /// Pull and push now (a synchronized database synchronizes on its own,
  /// this is "sync now"); nothing when not synchronized.
  Future<void> synchronize() async {
    await autoSyncedSdb?.synchronize();
  }

  /// True once the first pull from firestore succeeded (always for a
  /// database that is not synchronized): before it, an empty list means
  /// nothing.
  bool get isFirstSyncDone =>
      autoSyncedSdb?.synchronizer.isFirstSyncDone ?? true;

  /// Read every record again: forget the sync cursor, then synchronize;
  /// nothing when not synchronized.
  Future<void> resynchronize() async {
    var synced = autoSyncedSdb;
    if (synced == null) {
      return;
    }
    await synced.syncedSdb.scvSyncMetaInfoRef.delete(db);
    await synced.synchronize();
  }

  /// Wait for the first synchronization (may never complete offline);
  /// done at once when not synchronized.
  Future<void> initialSynchronizationDone() =>
      autoSyncedSdb?.initialSynchronizationDone() ?? Future.value();

  /// Close the database, and its synchronizer when synchronized (which
  /// closes the database).
  Future<void> close() async {
    var autoSyncedSdb = this.autoSyncedSdb;
    if (autoSyncedSdb != null) {
      await autoSyncedSdb.close();
    } else {
      await db.close();
    }
  }
}
