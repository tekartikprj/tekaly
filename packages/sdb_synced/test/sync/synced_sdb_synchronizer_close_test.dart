import 'dart:async';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb_firestore.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:test/test.dart';

/// A slow remote: reading the record list waits for [gate].
class _SlowSource with SyncedSourceDefaultMixin implements SyncedSource {
  final _inner = SyncedSourceMemory();
  var gate = Completer<void>()..complete();
  final _listing = StreamController<void>.broadcast(sync: true);

  /// Done when the next record list read starts.
  Future<void> nextListing() => _listing.stream.first;

  @override
  Future<CvMetaInfo?> getMetaInfo() => _inner.getMetaInfo();

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(
    SyncedDataSourceRef sourceRef,
  ) => _inner.getSourceRecord(sourceRef);

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) async {
    _listing.add(null);
    await gate.future;
    return _inner.getSourceRecordList(
      afterChangeId: afterChangeId,
      limit: limit,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) =>
      _inner.onMetaInfo(checkDelay: checkDelay);

  @override
  Future<CvMetaInfo> putMetaInfo(CvMetaInfo info) => _inner.putMetaInfo(info);

  @override
  Future<void> putRawRecord(CvSyncedSourceRecord record) =>
      _inner.putRawRecord(record);

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record) =>
      _inner.putSourceRecord(record);

  @override
  Future<void> close() => _inner.close();
}

final _store = SdbStoreRef<String, SdbModel>('my_store');

final _options = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [_store.schema(), ...syncedSdbMetaSchema.stores],
    ),
  ),
);

/// Run [body], failing on any uncaught error, even one raised once [body]
/// is done (a sync still running on a closed database).
Future<void> _noUncaughtError(Future<void> Function() body) async {
  var errors = <Object>[];
  var done = Completer<void>();
  runZonedGuarded(() {
    unawaited(() async {
      try {
        await body();
        // Let what is still running end.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        done.complete();
      } catch (e, st) {
        done.completeError(e, st);
      }
    }());
  }, (error, _) => errors.add(error));
  await done.future;
  expect(errors, isEmpty);
}

void main() {
  test('close waits for the running sync and the one queued behind it', () {
    return _noUncaughtError(() async {
      var source = _SlowSource();
      var syncedSdb = SyncedSdb.newInMemory(options: _options);
      var db = await syncedSdb.database;
      var synchronizer = SyncedSdbSynchronizer(db: syncedSdb, source: source);

      source.gate = Completer<void>();
      var listing = source.nextListing();
      await _store.record('k1').put(db, {'v': 1});
      var sync1 = Future.value(synchronizer.sync());
      await listing;
      // Changed during the sync: a new one is requested, it runs after.
      await _store.record('k2').put(db, {'v': 2});
      var sync2 = Future.value(synchronizer.sync());

      var closed = false;
      var close = () async {
        await synchronizer.close();
        await syncedSdb.close();
        closed = true;
      }();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(closed, isFalse);

      source.gate.complete();
      await close;
      expect((await sync1).notExecuted, isFalse);
      // It used to run on the closed database, never completing.
      await sync2.timeout(const Duration(seconds: 5));
      // Pushed before the close.
      expect(
        (await source.getSourceRecordList()).list.map((r) => r.recordKey),
        unorderedEquals(['k1', 'k2']),
      );
    });
  });

  test('close twice, lazy sync once closed', () {
    return _noUncaughtError(() async {
      var syncedSdb = SyncedSdb.newInMemory(options: _options);
      await syncedSdb.database;
      var synchronizer = SyncedSdbSynchronizer(
        db: syncedSdb,
        source: _SlowSource(),
        autoSync: true,
      );
      await synchronizer.lazySync();
      await Future.wait([synchronizer.close(), synchronizer.close()]);
      await synchronizer.close();
      await Future.wait([syncedSdb.close(), syncedSdb.close()]);
      // Used to never complete.
      var stat = await synchronizer.lazySync().timeout(
        const Duration(seconds: 5),
      );
      expect(stat.notExecuted, isTrue);
    });
  });

  test('reopened while closing, the database waits for the close', () {
    return _noUncaughtError(() async {
      var firestore = newFirestoreMemory();
      var databaseFactory = newSdbFactoryMemory();
      AutoSynchronizedFirestoreSyncedSdbOptions options() =>
          AutoSynchronizedFirestoreSyncedSdbOptions(
            firestore: firestore,
            databaseFactory: databaseFactory,
            dbName: 'reopen.db',
            rootDocumentPath: 'test/reopen',
            syncedSdbOptions: _options,
          );
      var first = await AutoSynchronizedFirestoreSyncedSdb.open(
        options: options(),
      );
      await first.initialSynchronizationDone();
      await _store.record('k1').put(first.database, {'v': 1});
      await first.synchronize();

      // A slow sync running: the close waits for it.
      var syncDone = Completer<void>();
      var syncing = first.synchronizer.syncLock.synchronized(
        () => syncDone.future,
      );
      var firstClose = first.close();
      var secondOpen = AutoSynchronizedFirestoreSyncedSdb.open(
        options: options(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      syncDone.complete();
      await syncing;
      await firstClose;
      var second = await secondOpen;
      // Not closed with the first one.
      expect((await _store.record('k1').get(second.database))?.value, {'v': 1});
      await _store.record('k2').put(second.database, {'v': 2});
      await second.synchronize();
      await second.close();
    });
  });
}
