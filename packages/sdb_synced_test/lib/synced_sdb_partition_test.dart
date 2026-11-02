import 'package:dev_test/test.dart';
import 'package:tekaly_sdb_synced/sdb_scv.dart';
import 'package:tekaly_sdb_synced/synced_sdb.dart';
import 'package:tekaly_sdb_synced/synced_source.dart'
    show SyncedSourcePartition;

/// Item of a user in the database.
class DbUserItem extends ScvStringRecordBase {
  final userId = CvField<String>('userId');
  final text = CvField<String>('text');

  @override
  List<CvField> get fields => [userId, text];
}

/// The partitioned store.
var sdbUserItemStoreRef = scvStringStoreFactory.store<DbUserItem>('user_item');

/// Database with the partitioned store.
var sdbUserItemOptions = SyncedSdbOptions(
  openDatabaseOptions: SdbOpenDatabaseOptions(
    version: 1,
    schema: SdbDatabaseSchema(
      stores: [sdbUserItemStoreRef.schema(), ...syncedSdbMetaSchema.stores],
    ),
  ),
);

/// Synchronizers of one location partitioned by user id: an admin reading
/// everything and users reading their own records.
///
/// [createPartitionedSource] creates a new location and returns its source
/// for a given partition.
void syncedSdbPartitionTests(
  Future<SyncedSource Function(SyncedSourcePartition? partition)> Function()
  createPartitionedSource,
) {
  const field = 'userId';
  cvAddConstructor(DbUserItem.new);

  group('partition', () {
    late SyncedSource Function(SyncedSourcePartition? partition) sourceOf;
    var closers = <Future<void> Function()>[];

    setUp(() async {
      sourceOf = await createPartitionedSource();
    });
    tearDown(() async {
      for (var close in closers.reversed) {
        await close();
      }
      closers.clear();
    });

    /// A device: its database and synchronizer, for [userId] or every user.
    Future<(SdbDatabase, SyncedSdbSynchronizer)> open({String? userId}) async {
      var syncedSdb = SyncedSdb.newInMemory(options: sdbUserItemOptions);
      var sync = SyncedSdbSynchronizer(
        db: syncedSdb,
        source: sourceOf(SyncedSourcePartition(field: field, value: userId)),
      );
      closers.add(() async {
        await sync.close();
        await syncedSdb.close();
      });
      return (await syncedSdb.database, sync);
    }

    Future<void> put(SdbDatabase db, String id, String? userId) =>
        (sdbUserItemStoreRef.record(id).cv()
              ..userId.v = userId
              ..text.v = 'text $id')
            .put(db);

    Future<List<String>> idsOf(SdbDatabase db) async => [
      for (var record in await sdbUserItemStoreRef.findRecords(db)) record.id,
    ];

    test('a user syncs only its records', () async {
      var (admin, adminSync) = await open();
      await put(admin, 'a', 'u1');
      await put(admin, 'b', 'u2');
      await put(admin, 'c', null);
      expect(await adminSync.sync(), SyncedSyncStat(remoteCreatedCount: 3));

      var (user1, user1Sync) = await open(userId: 'u1');
      expect(await user1Sync.sync(), SyncedSyncStat(localCreatedCount: 1));
      expect(await idsOf(user1), ['a']);
      expect(
        (await sdbUserItemStoreRef.record('a').get(user1))!.text.v,
        'text a',
      );

      var (user2, user2Sync) = await open(userId: 'u2');
      await user2Sync.sync();
      expect(await idsOf(user2), ['b']);

      // Changes of the other users: nothing to download.
      await put(admin, 'd', 'u2');
      await adminSync.sync();
      expect(await user1Sync.sync(), SyncedSyncStat());
      await put(admin, 'e', 'u1');
      await adminSync.sync();
      expect(await user1Sync.sync(), SyncedSyncStat(localCreatedCount: 1));
      expect(await idsOf(user1), ['a', 'e']);
    });

    test('a delete reaches the user', () async {
      var (admin, adminSync) = await open();
      await put(admin, 'a', 'u1');
      await put(admin, 'b', 'u1');
      await adminSync.sync();
      var (user1, user1Sync) = await open(userId: 'u1');
      await user1Sync.sync();
      expect(await idsOf(user1), ['a', 'b']);

      await sdbUserItemStoreRef.record('a').delete(admin);
      expect(await adminSync.sync(), SyncedSyncStat(remoteDeletedCount: 1));
      expect(await user1Sync.sync(), SyncedSyncStat(localDeletedCount: 1));
      expect(await idsOf(user1), ['b']);

      // A new device of the user never sees the deleted record.
      var (user1b, user1bSync) = await open(userId: 'u1');
      expect(await user1bSync.sync(), SyncedSyncStat(localCreatedCount: 1));
      expect(await idsOf(user1b), ['b']);
    });

    test('a user writes its own records', () async {
      var (admin, adminSync) = await open();
      var (user1, user1Sync) = await open(userId: 'u1');
      var (user1b, user1bSync) = await open(userId: 'u1');
      await put(user1, 'a', 'u1');
      expect(await user1Sync.sync(), SyncedSyncStat(remoteCreatedCount: 1));
      await adminSync.sync();
      await user1bSync.sync();
      expect(await idsOf(admin), ['a']);
      expect(await idsOf(user1b), ['a']);

      // Deleted by the user: the other device of the user sees it.
      await sdbUserItemStoreRef.record('a').delete(user1);
      expect(await user1Sync.sync(), SyncedSyncStat(remoteDeletedCount: 1));
      expect(await user1bSync.sync(), SyncedSyncStat(localDeletedCount: 1));
      expect(await adminSync.sync(), SyncedSyncStat(localDeletedCount: 1));
      expect(await idsOf(user1b), isEmpty);
      expect(await idsOf(admin), isEmpty);
    });

    test('a record moved to another user stays on the former one', () async {
      // The documented limitation: the former partition never sees the
      // change.
      var (admin, adminSync) = await open();
      await put(admin, 'a', 'u1');
      await adminSync.sync();
      var (user1, user1Sync) = await open(userId: 'u1');
      var (user2, user2Sync) = await open(userId: 'u2');
      await user1Sync.sync();
      await put(admin, 'a', 'u2');
      await adminSync.sync();
      expect(await user1Sync.sync(), SyncedSyncStat());
      expect(await idsOf(user1), ['a']);
      await user2Sync.sync();
      expect(await idsOf(user2), ['a']);
    });
  });
}
