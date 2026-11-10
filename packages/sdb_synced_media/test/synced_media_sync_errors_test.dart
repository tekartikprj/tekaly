import 'dart:typed_data';

import 'package:tekaly_sdb_synced/synced_source.dart';
import 'package:tekaly_sdb_synced_media/synced_media.dart';
import 'package:test/test.dart';

import 'synced_media_test_common.dart';

/// Memory source refusing to delete the paths of [undeletable].
class _UndeletableSource extends SyncedMediaSourceMemory {
  final undeletable = <String>{};

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) async {
    if (undeletable.contains(ref.path)) {
      throw StateError('delete of $ref denied');
    }
    await super.deleteMediaFile(ref);
  }
}

void main() {
  late SyncedSourceMemory source;
  late _UndeletableSource serverSource;
  late SyncedMediaSource mediaSource;
  var clients = <MediaClient>[];

  setUp(() {
    source = SyncedSourceMemory();
    serverSource = _UndeletableSource();
    // The server refuses the contents above 100 bytes.
    mediaSource = SyncedMediaSourceApi(
      client: SyncedMediaApiClientLocal(
        service: SyncedMediaApiService(source: serverSource, maxSize: 100),
      ),
    );
  });
  tearDown(() async {
    for (var client in clients) {
      await client.close();
    }
    clients.clear();
    await source.close();
  });

  Future<MediaClient> open() async {
    var client = await MediaClient.open(
      source: source,
      mediaSource: mediaSource,
    );
    clients.add(client);
    return client;
  }

  /// Media with a fixed id (the upload order is the id order).
  Future<String> add(MediaClient client, String uid, Uint8List bytes) =>
      client.mediaDb.addMediaFile(
        file: SyncedMediaFile(
          uid: uid,
          originalFilename: '$uid.bin',
          type: 'application/octet-stream',
          path: 'media/$uid.bin',
          size: bytes.length,
        ),
        bytes: bytes,
      );

  /// Another client publishes a media.
  Future<String> publishFromOther() async {
    var other = await open();
    var id = await add(other, 'z_other', bytesOfSize(10));
    await other.syncAll();
    expect(serverSource.paths, ['media/z_other.bin']);
    return id;
  }

  test('a refused upload does not block the others', () async {
    var otherId = await publishFromOther();
    var client = await open();
    // First in the upload order, refused for good.
    var bigId = await add(client, 'a_big', bytesOfSize(101));
    var smallId = await add(client, 'b_small', bytesOfSize(10));
    await client.dbSynchronizer.sync();
    await expectLater(
      client.mediaSynchronizer.sync(),
      throwsA(isA<SyncedMediaApiException>()),
    );
    expect(
      serverSource.paths,
      unorderedEquals(['media/z_other.bin', 'media/b_small.bin']),
    );
    expect(await client.isLocal(otherId), isTrue);
    expect(
      (await client.mediaDb.getMediaFileStatus(smallId))!.isRemote,
      isTrue,
    );
    // Still to upload, retried by the next sync.
    expect(await client.mediaDb.fileIdsToUpload(), [bigId]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a refused remote delete does not block the others', () async {
    var otherId = await publishFromOther();
    var client = await open();
    var aId = await add(client, 'a_kept', bytesOfSize(10));
    var bId = await add(client, 'b_deleted', bytesOfSize(10));
    await client.syncAll();
    serverSource.undeletable.add('media/a_kept.bin');
    await client.mediaDb.deleteMediaFile(aId);
    await client.mediaDb.deleteMediaFile(bId);
    await client.mediaDb.markLocalNotPresent(otherId);
    await client.mediaDb.updateStatus(otherId, remote: true);
    await expectLater(
      client.mediaSynchronizer.sync(),
      throwsA(isA<StateError>()),
    );
    expect(
      serverSource.paths,
      unorderedEquals(['media/z_other.bin', 'media/a_kept.bin']),
    );
    // Purged once deleted remotely only.
    expect(await client.mediaDb.getMediaFileRecord(bId), isNull);
    expect(await client.mediaDb.fileIdsToDeleteRemotely(), [aId]);
    // The download still ran.
    expect(await client.isLocal(otherId), isTrue);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
