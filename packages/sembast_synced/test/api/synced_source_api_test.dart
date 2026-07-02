import 'package:cv/cv.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/src/api/model/api_models.dart';
import 'package:tekaly_sembast_synced/src/api/model/api_sync.dart';
import 'package:tekaly_sembast_synced/src/api/secure_client.dart';
import 'package:tekaly_sembast_synced/src/api/sync_api.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source_api.dart';
import 'package:tekaly_sembast_synced/src/sembast/sembast_import.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:test/test.dart';

/// In-memory fake [ApiService] recording the last request and replying with
/// a pre-configured response.
class _FakeApiService implements ApiService {
  String? lastCommand;
  CvModel? lastRequest;
  CvModel? Function(String command, CvModel request)? onSend;

  @override
  Future<T> send<T extends CvModel>(String command, CvModel request) async {
    lastCommand = command;
    lastRequest = request;
    var response = onSend?.call(command, request);
    return response as T;
  }
}

CvSyncedSourceRecord _newRecord({
  String? syncId,
  required String store,
  required String key,
  Model? value,
  int? syncChangeId,
  Timestamp? syncTimestamp,
}) {
  return CvSyncedSourceRecord()
    ..syncId.v = syncId
    ..syncChangeId.v = syncChangeId
    ..syncTimestamp.v = syncTimestamp
    ..record.v = (CvSyncedSourceRecordData()
      ..store.v = store
      ..key.v = key
      ..value.v = value);
}

void main() {
  initApiBuilders();

  group('jsonEncodeSembastValueOrNull/jsonDecodeSembastValueOrNull', () {
    test('null', () {
      expect(jsonEncodeSembastValueOrNull(null), isNull);
      expect(jsonDecodeSembastValueOrNull(null), isNull);
    });

    test('round trip a map value', () {
      var value = <String, Object?>{'a': 1, 'b': 'text'};
      var encoded = jsonEncodeSembastValueOrNull(value);
      expect(jsonDecodeSembastValueOrNull(encoded), value);
    });

    test('round trip a nested DbTimestamp value', () {
      var dbTimestamp = DbTimestamp(1000, 2000);
      var value = <String, Object?>{'ts': dbTimestamp};
      var encoded = jsonEncodeSembastValueOrNull(value);
      // Encoded as a json encodable representation, not the raw object.
      expect(encoded, {
        'ts': {'@timestamp': '1970-01-01T00:16:40.000002Z'},
      });
      expect(jsonDecodeSembastValueOrNull(encoded), value);
    });

    test('round trip a nested DbBlob value', () {
      var dbBlob = DbBlob.fromList([1, 2, 3]);
      var value = <String, Object?>{'blob': dbBlob};
      var encoded = jsonEncodeSembastValueOrNull(value);
      expect(encoded, {
        'blob': {'@blob': 'AQID'},
      });
      expect(jsonDecodeSembastValueOrNull(encoded), value);
    });

    test('round trip all types', () {
      var decoded = {
        'null': null,
        'int': 1,
        'listList': [1, 2, 3],
        'string': 'text',
        'timestamp': Timestamp.fromMicrosecondsSinceEpoch(1),
        'blob': DbBlob.fromList([1, 2, 3]),

        'looksLikeTimestamp': {r'$timestamp': '1970-01-01T00:00:00.000001Z'},
        'looksLikeBlob': {r'$Blob': 'AQID'},
        'looksLikeDummy': {r'$': null},

        'looksLikeTimestampLegacy': {
          '@Timestamp': '1970-01-01T00:00:00.000001Z',
        },
        'looksLikeBlobLegacy': {'@Blob': 'AQID'},
        'looksLikeDummyLegacy': {'@': null},
      };
      var encoded = {
        'null': null,
        'int': 1,
        'listList': [1, 2, 3],
        'string': 'text',
        'timestamp': {r'$timestamp': '1970-01-01T00:00:00.000001Z'},
        'blob': {r'$blob': 'AQID'},
        'looksLikeTimestamp': {
          r'$': {r'$timestamp': '1970-01-01T00:00:00.000001Z'},
        },
        'looksLikeBlob': {
          r'$': {r'$Blob': 'AQID'},
        },
        'looksLikeDummy': {
          r'$': {r'$': null},
        },
        'looksLikeTimestampLegacy': {
          r'@Timestamp': '1970-01-01T00:00:00.000001Z',
        },
        'looksLikeBlobLegacy': {r'@Blob': 'AQID'},
        'looksLikeDummyLegacy': {r'@': null},
      };
      expect(jsonEncodeSembastValueOrNull(decoded), encoded);
      expect(jsonDecodeSembastValueOrNull(encoded), decoded);
    });
  });

  group('parseTimestamp', () {
    test('null', () {
      expect(parseTimestamp(null), isNull);
    });

    test('invalid', () {
      expect(parseTimestamp('not-a-timestamp'), isNull);
    });

    test('valid', () {
      var timestamp = Timestamp(1000, 0);
      expect(parseTimestamp(timestamp.toIso8601String()), timestamp);
    });
  });

  group('apiChangeRefToRecordRef', () {
    test('converts fields', () {
      var change = ApiChangeRef()
        ..syncId.v = 'sync-1'
        ..store.v = 'store-1'
        ..key.v = 'key-1';
      var ref = apiChangeRefToRecordRef(change);
      expect(ref.syncId, 'sync-1');
      expect(ref.store, 'store-1');
      expect(ref.key, 'key-1');
    });
  });

  group('recordRefToSyncChangeRef', () {
    test('converts fields', () {
      var ref = SyncedDataSourceRef(
        syncId: 'sync-1',
        store: 'store-1',
        key: 'key-1',
      );
      var change = ApiChangeRef();
      recordRefToSyncChangeRef(ref, change);
      expect(change.syncId.v, 'sync-1');
      expect(change.store.v, 'store-1');
      expect(change.key.v, 'key-1');
    });
  });

  group('recordToSyncChangeRef', () {
    test('converts fields from nested record data', () {
      var record = _newRecord(syncId: 'sync-1', store: 'store-1', key: 'key-1');
      var change = ApiChangeRef();
      recordToSyncChangeRef(record, change);
      expect(change.syncId.v, 'sync-1');
      expect(change.store.v, 'store-1');
      expect(change.key.v, 'key-1');
    });
  });

  group('apiChangeToRecord', () {
    test('with data is not deleted', () {
      var timestamp = Timestamp(1000, 0);
      var change = ApiChange()
        ..syncId.v = 'sync-1'
        ..store.v = 'store-1'
        ..key.v = 'key-1'
        ..changeNum.v = 42
        ..timestamp.v = timestamp.toIso8601String()
        ..data.v = jsonEncodeSembastValueOrNull({'a': 1}) as Model;

      var record = apiChangeToRecord(change);
      expect(record.syncId.v, 'sync-1');
      expect(record.syncChangeId.v, 42);
      expect(record.syncTimestamp.v, timestamp);
      expect(record.record.v!.store.v, 'store-1');
      expect(record.record.v!.key.v, 'key-1');
      expect(record.record.v!.value.v, {'a': 1});
      expect(record.record.v!.deleted.v, isFalse);
    });

    test('without data is deleted', () {
      var change = ApiChange()
        ..syncId.v = 'sync-1'
        ..store.v = 'store-1'
        ..key.v = 'key-1';

      var record = apiChangeToRecord(change);
      expect(record.record.v!.value.v, isNull);
      expect(record.record.v!.deleted.v, isTrue);
      expect(record.syncTimestamp.v, isNull);
    });

    test('with a nested DbTimestamp value', () {
      var dbTimestamp = DbTimestamp(1000, 0);
      var change = ApiChange()
        ..store.v = 'store-1'
        ..key.v = 'key-1'
        ..data.v = jsonEncodeSembastValueOrNull({'ts': dbTimestamp}) as Model;

      var record = apiChangeToRecord(change);
      expect(record.record.v!.value.v, {'ts': dbTimestamp});
    });

    test('with a nested DbBlob value', () {
      var dbBlob = DbBlob.fromList([1, 2, 3]);
      var change = ApiChange()
        ..store.v = 'store-1'
        ..key.v = 'key-1'
        ..data.v = jsonEncodeSembastValueOrNull({'blob': dbBlob}) as Model;

      var record = apiChangeToRecord(change);
      expect(record.record.v!.value.v, {'blob': dbBlob});
    });
  });

  group('recordToSyncChange', () {
    test('converts a record with a value', () {
      var timestamp = Timestamp(1000, 0);
      var record = _newRecord(
        syncId: 'sync-1',
        store: 'store-1',
        key: 'key-1',
        value: {'a': 1},
        syncChangeId: 42,
        syncTimestamp: timestamp,
      );

      var change = ApiChange();
      recordToSyncChange(record, change);
      expect(change.syncId.v, 'sync-1');
      expect(change.store.v, 'store-1');
      expect(change.key.v, 'key-1');
      expect(change.changeNum.v, 42);
      expect(change.timestamp.v, timestamp.toIso8601String());
      expect(jsonDecodeSembastValueOrNull(change.data.v), {'a': 1});
    });

    test('converts a record with a nested DbTimestamp value', () {
      var dbTimestamp = DbTimestamp(1000, 0);
      var record = _newRecord(
        store: 'store-1',
        key: 'key-1',
        value: {'ts': dbTimestamp},
      );

      var change = ApiChange();
      recordToSyncChange(record, change);
      expect(jsonDecodeSembastValueOrNull(change.data.v), {'ts': dbTimestamp});
    });

    test('converts a record with a nested DbBlob value', () {
      var dbBlob = DbBlob.fromList([1, 2, 3]);
      var record = _newRecord(
        store: 'store-1',
        key: 'key-1',
        value: {'blob': dbBlob},
      );

      var change = ApiChange();
      recordToSyncChange(record, change);
      expect(jsonDecodeSembastValueOrNull(change.data.v), {'blob': dbBlob});
    });

    test('round trips through apiChangeToRecord', () {
      var timestamp = Timestamp(1000, 0);
      var record = _newRecord(
        syncId: 'sync-1',
        store: 'store-1',
        key: 'key-1',
        value: {'a': 1},
        syncChangeId: 42,
        syncTimestamp: timestamp,
      );

      var change = ApiChange();
      recordToSyncChange(record, change);
      var result = apiChangeToRecord(change);

      expect(result.syncId.v, record.syncId.v);
      expect(result.syncChangeId.v, record.syncChangeId.v);
      expect(result.syncTimestamp.v, record.syncTimestamp.v);
      expect(result.record.v!.store.v, record.record.v!.store.v);
      expect(result.record.v!.key.v, record.record.v!.key.v);
      expect(result.record.v!.value.v, record.record.v!.value.v);
    });
  });

  group('syncInfoToMeta/metaToSyncInfo', () {
    test('syncInfoToMeta converts fields', () {
      var info = ApiSyncInfo()
        ..version.v = 1
        ..minIncrementalChangeNum.v = 2
        ..lastChangeNum.v = 3;
      var meta = syncInfoToMeta(info);
      expect(meta.version.v, 1);
      expect(meta.minIncrementalChangeId.v, 2);
      expect(meta.lastChangeId.v, 3);
    });

    test('metaToSyncInfo converts fields', () {
      var meta = CvMetaInfo()
        ..version.v = 1
        ..minIncrementalChangeId.v = 2
        ..lastChangeId.v = 3;
      var info = ApiSyncInfo();
      metaToSyncInfo(meta, info);
      expect(info.version.v, 1);
      expect(info.minIncrementalChangeNum.v, 2);
      expect(info.lastChangeNum.v, 3);
    });
  });

  group('SyncedSourceApi', () {
    late _FakeApiService apiService;
    late SyncedSourceApi source;

    setUp(() {
      apiService = _FakeApiService();
      source = SyncedSourceApi(apiService: apiService, target: 'my-target');
    });

    test('getMetaInfo sends the target and maps the response', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncGetInfo);
        expect((request as ApiGetSyncInfoRequest).target.v, 'my-target');
        return ApiGetSyncInfoResponse()
          ..version.v = 1
          ..minIncrementalChangeNum.v = 2
          ..lastChangeNum.v = 3;
      };

      var meta = await source.getMetaInfo();
      expect(meta!.version.v, 1);
      expect(meta.minIncrementalChangeId.v, 2);
      expect(meta.lastChangeId.v, 3);
    });

    test('getSourceRecord returns null when key is missing', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncGetChange);
        return ApiGetChangeResponse();
      };

      var ref = SyncedDataSourceRef(store: 'store-1', key: 'key-1');
      var record = await source.getSourceRecord(ref);
      expect(record, isNull);
    });

    test('getSourceRecord returns a record when found', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncGetChange);
        var getRequest = request as ApiGetChangeRequest;
        expect(getRequest.target.v, 'my-target');
        expect(getRequest.store.v, 'store-1');
        expect(getRequest.key.v, 'key-1');
        return ApiGetChangeResponse()
          ..store.v = 'store-1'
          ..key.v = 'key-1'
          ..data.v = jsonEncodeSembastValueOrNull({'a': 1}) as Model;
      };

      var ref = SyncedDataSourceRef(store: 'store-1', key: 'key-1');
      var record = await source.getSourceRecord(ref);
      expect(record!.record.v!.store.v, 'store-1');
      expect(record.record.v!.key.v, 'key-1');
      expect(record.record.v!.value.v, {'a': 1});
    });

    test('getSourceRecordList maps the changes and last change id', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncGetChanges);
        var getRequest = request as ApiGetChangesRequest;
        expect(getRequest.target.v, 'my-target');
        expect(getRequest.afterChangeNum.v, 10);
        expect(getRequest.includeDeleted.v, isNull);
        return ApiGetChangesResponse()
          ..lastChangeNum.v = 12
          ..changes.v = [
            ApiChange()
              ..store.v = 'store-1'
              ..key.v = 'key-1'
              ..changeNum.v = 11,
            ApiChange()
              ..store.v = 'store-1'
              ..key.v = 'key-2'
              ..changeNum.v = 12,
          ];
      };

      var result = await source.getSourceRecordList(afterChangeId: 10);
      expect(result.length, 2);
      expect(result.lastChangeId, 12);
      expect(result.list.first.record.v!.key.v, 'key-1');
      expect(result.list.last.record.v!.key.v, 'key-2');
    });

    test('getSourceRecordList falls back to syncInfo last change id', () async {
      apiService.onSend = (command, request) {
        return ApiGetChangesResponse()
          ..syncInfo.v = (ApiSyncInfo()..lastChangeNum.v = 99)
          ..changes.v = [
            ApiChange()
              ..store.v = 'store-1'
              ..key.v = 'key-1'
              ..changeNum.v = 5,
          ];
      };

      var result = await source.getSourceRecordList();
      expect(result.lastChangeId, 99);
    });

    test('getSourceRecordList sets includeDeleted when true', () async {
      apiService.onSend = (command, request) {
        var getRequest = request as ApiGetChangesRequest;
        expect(getRequest.includeDeleted.v, isTrue);
        return ApiGetChangesResponse()..changes.v = [];
      };

      var result = await source.getSourceRecordList(includeDeleted: true);
      expect(result.isEmpty, isTrue);
      expect(result.lastChangeId, isNull);
    });

    test('putMetaInfo sends info and maps the response', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncPutInfo);
        var putRequest = request as ApiPutSyncInfoRequest;
        expect(putRequest.target.v, 'my-target');
        expect(putRequest.lastChangeNum.v, 3);
        expect(putRequest.minIncrementalChangeNum.v, 2);
        expect(putRequest.version.v, 1);
        return ApiPutSyncInfoResponse()
          ..version.v = 1
          ..minIncrementalChangeNum.v = 2
          ..lastChangeNum.v = 3;
      };

      var info = CvMetaInfo()
        ..version.v = 1
        ..minIncrementalChangeId.v = 2
        ..lastChangeId.v = 3;
      var result = await source.putMetaInfo(info);
      expect(result.version.v, 1);
      expect(result.minIncrementalChangeId.v, 2);
      expect(result.lastChangeId.v, 3);
    });

    test('putSourceRecord sends the record and maps the response', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncPutChange);
        var putRequest = request as ApiPutChangeRequest;
        expect(putRequest.target.v, 'my-target');
        expect(putRequest.store.v, 'store-1');
        expect(putRequest.key.v, 'key-1');
        return ApiPutChangeResponse()
          ..store.v = 'store-1'
          ..key.v = 'key-1'
          ..changeNum.v = 7;
      };

      var record = _newRecord(store: 'store-1', key: 'key-1');
      var result = await source.putSourceRecord(record);
      expect(result.syncChangeId.v, 7);
    });

    test('putRawRecord sends the raw command', () async {
      apiService.onSend = (command, request) {
        expect(command, commandSyncPutRawChange);
        return ApiPutChangeResponse();
      };

      var record = _newRecord(store: 'store-1', key: 'key-1');
      await source.putRawRecord(record);
      expect(apiService.lastCommand, commandSyncPutRawChange);
    });
  });
}
