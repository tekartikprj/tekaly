// The failure injection is a test only member.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sembast_synced/synced_db.dart';
import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:test/test.dart';

/// Short delays, the tests must not wait for the default 5s/15s.
const _fastRetryOptions = SyncedDbSynchronizerRetryOptions(
  firstSyncDelay: Duration(milliseconds: 20),
  delay: Duration(milliseconds: 20),
  maxDelay: Duration(milliseconds: 40),
  permanentErrorDelay: Duration(minutes: 10),
);

const _retryingActivities = [
  SyncedDbSyncActivity.retryScheduled,
  SyncedDbSyncActivity.syncing,
];

const _storeName = 'entity';
const _timeout = Duration(seconds: 5);

final _sdbStoreRef = SdbStoreRef<String, SdbModel>(_storeName);
final _sdbOptions = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [_sdbStoreRef.schema(), ...syncedSdbMetaSchema.stores],
    ),
  ),
);
final _sembastStoreRef = stringMapStoreFactory.store(_storeName);

/// A local database, able to create several synchronizers (sessions).
abstract class _LocalDb {
  SyncedDbSynchronizerCommon newSynchronizer({
    SyncedSource? source,
    SyncedSourceRead? readSource,
    bool autoSync = false,
  });

  Future<void> putRecord(String key, Map<String, Object?> value);

  Future<Map<String, Object?>?> getRecord(String key);

  Future<void> close();
}

class _SembastLocalDb implements _LocalDb {
  final SyncedDb db;

  _SembastLocalDb(this.db);

  @override
  SyncedDbSynchronizerCommon newSynchronizer({
    SyncedSource? source,
    SyncedSourceRead? readSource,
    bool autoSync = false,
  }) => SyncedDbSynchronizer(
    db: db,
    source: source,
    readSource: readSource,
    autoSync: autoSync,
    retryOptions: _fastRetryOptions,
  );

  @override
  Future<void> putRecord(String key, Map<String, Object?> value) async {
    await _sembastStoreRef.record(key).put(await db.database, value);
  }

  @override
  Future<Map<String, Object?>?> getRecord(String key) async =>
      _sembastStoreRef.record(key).get(await db.database);

  @override
  Future<void> close() => db.close();
}

class _SdbLocalDb implements _LocalDb {
  final SyncedSdb db;

  _SdbLocalDb(this.db);

  @override
  SyncedDbSynchronizerCommon newSynchronizer({
    SyncedSource? source,
    SyncedSourceRead? readSource,
    bool autoSync = false,
  }) => SyncedSdbSynchronizer(
    db: db,
    source: source,
    readSource: readSource,
    autoSync: autoSync,
    retryOptions: _fastRetryOptions,
  );

  @override
  Future<void> putRecord(String key, Map<String, Object?> value) async {
    await _sdbStoreRef.record(key).put(await db.database, value);
  }

  @override
  Future<Map<String, Object?>?> getRecord(String key) async =>
      (await _sdbStoreRef.record(key).get(await db.database))?.value;

  @override
  Future<void> close() => db.close();
}

final _implementations = <String, Future<_LocalDb> Function()>{
  'sembast': () async {
    var db = SyncedDb.newInMemory(syncedStoreNames: [_storeName]);
    await db.database;
    return _SembastLocalDb(db);
  },
  'sdb': () async {
    var db = SyncedSdb.newInMemory(options: _sdbOptions);
    await db.database;
    return _SdbLocalDb(db);
  },
};

extension on SyncedDbSynchronizerCommon {
  Future<SyncedDbSyncStatus> statusWhere(
    bool Function(SyncedDbSyncStatus status) test,
  ) => onSyncStatus().firstWhere(test).timeout(_timeout);
}

void main() {
  for (var entry in _implementations.entries) {
    group('synced_db_sync_status_${entry.key}', () {
      late SyncedSourceMemory source;
      late _LocalDb localDb;
      final synchronizers = <SyncedDbSynchronizerCommon>[];

      SyncedDbSynchronizerCommon newSynchronizer({
        bool autoSync = false,
        bool readOnly = false,
      }) {
        var synchronizer = readOnly
            ? localDb.newSynchronizer(readSource: source, autoSync: autoSync)
            : localDb.newSynchronizer(source: source, autoSync: autoSync);
        synchronizers.add(synchronizer);
        return synchronizer;
      }

      setUp(() async {
        source = SyncedSourceMemory();
        localDb = await entry.value();
      });

      tearDown(() async {
        for (var synchronizer in synchronizers) {
          await synchronizer.close();
        }
        synchronizers.clear();
        await localDb.close();
        await source.close();
      });

      test('never then this session', () async {
        var synchronizer = newSynchronizer();
        var status = await synchronizer.statusWhere(
          (status) => status.initialSync != SyncedDbInitialSync.unknown,
        );
        expect(status.initialSync, SyncedDbInitialSync.never);
        expect(status.activity, SyncedDbSyncActivity.idle);
        expect(status.isInitialSyncDone, isFalse);
        expect(status.lastSyncTime, isNull);

        await synchronizer.sync();
        status = synchronizer.syncStatus;
        expect(status.initialSync, SyncedDbInitialSync.thisSession);
        expect(status.activity, SyncedDbSyncActivity.idle);
        expect(status.lastSyncTime, isNotNull);
        expect(status.satisfies(SyncedDbInitialSyncPolicy.thisSession), isTrue);
      });

      test('first sync failing then retried', () async {
        source.failureControl.fail();
        var synchronizer = newSynchronizer(autoSync: true);
        // The local meta info is read asynchronously.
        var status = await synchronizer.statusWhere(
          (status) =>
              status.activity == SyncedDbSyncActivity.retryScheduled &&
              status.initialSync != SyncedDbInitialSync.unknown,
        );
        expect(status.initialSync, SyncedDbInitialSync.never);
        expect(status.lastError, isA<SyncedSourceFailureException>());
        expect(status.failureCount, greaterThanOrEqualTo(1));
        expect(status.retryingSince, isNotNull);
        expect(status.nextRetryTime, isNotNull);

        // A timeout gives the current status back, without throwing.
        status = await synchronizer.waitInitialSync(
          timeout: const Duration(milliseconds: 50),
        );
        expect(status.isInitialSyncDone, isFalse);

        source.failureControl.stop();
        status = await synchronizer
            .waitInitialSync(policy: SyncedDbInitialSyncPolicy.thisSession)
            .timeout(_timeout);
        expect(status.initialSync, SyncedDbInitialSync.thisSession);
        status = await synchronizer.statusWhere(
          (status) => status.activity == SyncedDbSyncActivity.idle,
        );
        expect(status.lastError, isNull);
        expect(status.failureCount, 0);
        expect(status.nextRetryTime, isNull);
      });

      test('previous session', () async {
        await newSynchronizer().sync();

        // A new session, offline.
        source.failureControl.fail();
        var synchronizer = newSynchronizer(autoSync: true);
        var status = await synchronizer.waitInitialSync().timeout(_timeout);
        expect(status.initialSync, SyncedDbInitialSync.previousSession);
        status = await synchronizer.waitInitialSync(
          policy: SyncedDbInitialSyncPolicy.thisSession,
          timeout: const Duration(milliseconds: 100),
        );
        expect(status.initialSync, SyncedDbInitialSync.previousSession);
        // Retrying every 20ms.
        expect(status.activity, isIn(_retryingActivities));

        source.failureControl.stop();
        status = await synchronizer
            .waitInitialSync(policy: SyncedDbInitialSyncPolicy.thisSession)
            .timeout(_timeout);
        expect(status.initialSync, SyncedDbInitialSync.thisSession);
      });

      test('permanent error, request sync', () async {
        source.failureControl.fail(
          error: SyncedSourcePermanentException(
            'no access',
            code: 'permission-denied',
          ),
        );
        var synchronizer = newSynchronizer(autoSync: true);
        var status = await synchronizer.statusWhere(
          (status) => status.activity == SyncedDbSyncActivity.failed,
        );
        expect(status.lastError, isA<SyncedSourcePermanentException>());
        // Slow retry (10mn in this test).
        expect(
          status.nextRetryTime!.difference(DateTime.timestamp()),
          greaterThan(const Duration(minutes: 5)),
        );

        // Access granted, retry now.
        source.failureControl.stop();
        synchronizer.requestSync();
        status = await synchronizer
            .waitInitialSync(policy: SyncedDbInitialSyncPolicy.thisSession)
            .timeout(_timeout);
        expect(status.initialSync, SyncedDbInitialSync.thisSession);
      });

      test('a permanent push error does not prevent the pull', () async {
        await source.putSourceRecord(
          CvSyncedSourceRecord()
            ..record.v = (CvSyncedSourceRecordData()
              ..store.v = _storeName
              ..key.v = 'remote'
              ..value.v = {'value': 1}),
        );
        await localDb.putRecord('local', {'value': 2});
        source.failureControl.fail(
          error: SyncedSourcePermanentException('rejected'),
          operations: [SyncedSourceOperation.putSourceRecord],
        );
        var synchronizer = newSynchronizer();
        await expectLater(
          Future<Object?>.value(synchronizer.sync()),
          throwsA(isA<SyncedSourcePermanentException>()),
        );
        expect(await localDb.getRecord('remote'), {'value': 1});
        expect(synchronizer.isFirstSyncDone, isTrue);
        // The dirty records are read asynchronously.
        var status = await synchronizer.statusWhere(
          (status) =>
              status.activity == SyncedDbSyncActivity.failed &&
              status.hasLocalChanges,
        );
        expect(status.initialSync, SyncedDbInitialSync.thisSession);
      });

      test('local changes', () async {
        var synchronizer = newSynchronizer();
        var status = await synchronizer.statusWhere(
          (status) => status.initialSync != SyncedDbInitialSync.unknown,
        );
        expect(status.hasLocalChanges, isFalse);
        await localDb.putRecord('local', {'value': 1});
        await synchronizer.statusWhere((status) => status.hasLocalChanges);
        await synchronizer.sync();
        expect(synchronizer.syncStatus.hasLocalChanges, isFalse);
      });

      test('read-only', () async {
        var synchronizer = newSynchronizer(readOnly: true);
        await synchronizer.sync();
        await localDb.putRecord('local', {'value': 1});
        await synchronizer.sync();
        var status = synchronizer.syncStatus;
        expect(status.readOnly, isTrue);
        expect(status.hasLocalChanges, isFalse);
        expect(status.initialSync, SyncedDbInitialSync.thisSession);
      });

      test('close completes the waits', () async {
        source.failureControl.fail();
        var synchronizer = newSynchronizer(autoSync: true);
        var future = synchronizer.waitInitialSync();
        var statuses = <SyncedDbSyncStatus>[];
        var done = synchronizer
            .onSyncStatus()
            .listen(statuses.add)
            .asFuture<void>();
        await synchronizer.statusWhere(
          (status) => status.activity == SyncedDbSyncActivity.retryScheduled,
        );
        await synchronizer.close();
        var status = await future.timeout(_timeout);
        expect(status.activity, SyncedDbSyncActivity.closed);
        expect(status.isInitialSyncDone, isFalse);
        await done.timeout(_timeout);
        expect(statuses.last.activity, SyncedDbSyncActivity.closed);
      });
    });
  }
}
