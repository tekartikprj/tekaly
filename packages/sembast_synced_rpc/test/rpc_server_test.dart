import 'dart:async';

import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_client.dart';
import 'package:tekaly_sembast_synced_rpc/rpc_server.dart';
import 'package:test/test.dart';

/// Memory source whose meta info can be deleted, counting the meta info
/// listeners (one per client wait).
class _TestSource extends SyncedSourceMemory {
  var metaInfoDeleted = false;
  var onMetaInfoCount = 0;

  /// Number of the next meta info reads that fail.
  var getMetaInfoFailureCount = 0;

  @override
  Future<CvMetaInfo?> getMetaInfo() async {
    if (getMetaInfoFailureCount > 0) {
      getMetaInfoFailureCount--;
      throw StateError('getMetaInfo failure');
    }
    var metaInfo = await super.getMetaInfo();
    return metaInfoDeleted ? null : metaInfo;
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) {
    onMetaInfoCount++;
    return super.onMetaInfo(checkDelay: const Duration(milliseconds: 20));
  }
}

void main() {
  rpcTests(webSocketChannelFactoryMemory);
}

/// Rpc tests
void rpcTests(WebSocketChannelFactory factory) {
  group('rpc', () {
    late _TestSource delegate;
    late SyncedSourceRpcServer rpcServer;
    late SyncedSourceRpcClient rpcClient;
    setUp(() async {
      delegate = _TestSource();
      rpcServer = await SyncedSourceRpcServer.serve(
        delegate: delegate,
        webSocketChannelServerFactory: factory.server,
      );
      rpcClient = SyncedSourceRpcClient(
        uri: rpcServer.uri,
        webSocketChannelClientFactory: factory.client,
      );
    });

    tearDown(() async {
      await rpcClient.close();
      await rpcServer.close();
    });

    test('onMetaInfo first read failure', () async {
      delegate.getMetaInfoFailureCount = 1;
      var errors = <Object>[];
      var uncaughtErrors = <Object>[];
      var firstEvent = Completer<CvMetaInfo?>();
      late StreamSubscription<CvMetaInfo?> subscription;
      runZonedGuarded(() {
        subscription = rpcClient.onMetaInfo().listen((event) {
          if (!firstEvent.isCompleted) {
            firstEvent.complete(event);
          }
        }, onError: errors.add);
      }, (e, _) => uncaughtErrors.add(e));
      // Reported then read again
      expect(
        await firstEvent.future.timeout(const Duration(seconds: 10)),
        isNull,
      );
      expect(errors, hasLength(1));
      expect(uncaughtErrors, isEmpty);
      await subscription.cancel();
    });

    test('onMetaInfo after the meta info is deleted', () async {
      await delegate.putMetaInfo(CvMetaInfo()..lastChangeId.v = 1);
      var events = <CvMetaInfo?>[];
      var deleted = Completer<void>();
      var subscription = rpcClient.onMetaInfo().listen((event) {
        events.add(event);
        if (event == null && !deleted.isCompleted) {
          deleted.complete();
        }
      });
      while (events.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(events.single?.lastChangeId.v, 1);
      delegate.metaInfoDeleted = true;
      await deleted.future.timeout(const Duration(seconds: 10));
      var count = delegate.onMetaInfoCount;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // The client waits for the next change (no request loop)
      expect(delegate.onMetaInfoCount - count, lessThanOrEqualTo(1));
      expect(events.map((event) => event?.lastChangeId.v), [1, null]);
      await subscription.cancel();
    });

    test('close stops the meta info stream', () async {
      var done = Completer<void>();
      var events = <CvMetaInfo?>[];
      rpcClient.onMetaInfo().listen(events.add, onDone: done.complete);
      while (events.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await rpcClient.close();
      await done.future.timeout(const Duration(seconds: 10));
      var count = delegate.onMetaInfoCount;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // No more requests once closed
      expect(delegate.onMetaInfoCount, count);
      await expectLater(rpcClient.getMetaInfo(), throwsStateError);
    });
  });
}
