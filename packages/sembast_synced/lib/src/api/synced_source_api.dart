import 'dart:async';

import 'package:cv/cv.dart';

// ignore: implementation_imports
import 'package:sembast/src/api/protected/codec.dart';
import 'package:sembast/timestamp.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_source.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';

import '../sync/model/source_meta_info.dart';
import 'model/api_models.dart';
import 'model/api_sync.dart';
import 'secure_client.dart';
import 'sync_api.dart';

/// Api model
class CvMetaInfoRecordApi extends CvModelBase with CvMetaInfoRecordMixin {}

var _codec = sembastCodecJsonEncodableCodec(null);
Object? jsonEncodeSembastValueOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _codec.encode(value);
}

Object? jsonDecodeSembastValueOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _codec.decode(value);
}

class SyncedSourceApi with SyncedSourceDefaultMixin implements SyncedSource {
  final ApiService apiService;
  final String target;

  @override
  Future<void> close() async {}
  SyncedSourceApi({required this.apiService, required this.target}) {
    initApiBuilders();
  }

  @override
  Future<CvMetaInfoRecord?> getMetaInfo() async {
    var apiResponse = await apiService.send<ApiGetSyncInfoResponse>(
      commandSyncGetInfo,
      ApiGetSyncInfoRequest()..target.v = target,
    );
    return syncInfoToMeta(apiResponse);
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(
    SyncedDataSourceRef sourceRef,
  ) async {
    var request = ApiGetChangeRequest();
    request.target.v = target;
    recordRefToSyncChangeRef(sourceRef, request);

    var apiResponse = await apiService.send<ApiGetChangeResponse>(
      commandSyncGetChange,
      request,
    );
    if (apiResponse.key.v == null) {
      return null;
    }
    return apiChangeToRecord(apiResponse);
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
    @Deprecated('Not used') String? pageToken,
  }) async {
    includeDeleted ??= false;
    var apiResponse = await apiService.send<ApiGetChangesResponse>(
      commandSyncGetChanges,
      ApiGetChangesRequest()
        ..target.v = target
        ..includeDeleted.setValue(includeDeleted ? true : null)
        ..afterChangeNum.v = afterChangeId
        ..limit.v,
    );
    var list = <CvSyncedSourceRecord>[];
    var lastChangeId = apiResponse.lastChangeNum.v;
    for (var change in apiResponse.changes.v ?? <ApiChange>[]) {
      list.add(apiChangeToRecord(change));
    }
    if (list.isNotEmpty) {
      lastChangeId ??= apiResponse.syncInfo.v?.lastChangeNum.v;
    }
    var result = SyncedSourceRecordList(list, lastChangeId);
    return result;
  }

  @override
  Future<CvMetaInfoRecord?> putMetaInfo(CvMetaInfoRecord info) async {
    var apiResponse = await apiService.send<ApiPutSyncInfoResponse>(
      commandSyncPutInfo,
      ApiPutSyncInfoRequest()
        ..target.v = target
        ..lastChangeNum.v = info.lastChangeId.v
        ..minIncrementalChangeNum.v = info.minIncrementalChangeId.v
        ..version.v = info.version.v,
    );
    return CvMetaInfoRecordApi()
      ..version.v = apiResponse.version.v
      ..minIncrementalChangeId.v = apiResponse.minIncrementalChangeNum.v
      ..lastChangeId.v = apiResponse.lastChangeNum.v;
  }

  @override
  Future<CvSyncedSourceRecord?> putSourceRecord(
    CvSyncedSourceRecord record,
  ) async {
    var request = ApiPutChangeRequest()..target.v = target;
    recordToSyncChange(record, request);
    var apiResponse = await apiService.send<ApiPutChangeResponse>(
      commandSyncPutChange,
      request,
    );
    return apiChangeToRecord(apiResponse);
  }

  @override
  Future<void> putRawRecord(CvSyncedSourceRecord record) async {
    var request = ApiPutChangeRequest()..target.v = target;
    recordToSyncChange(record, request);
    await apiService.send<ApiPutChangeResponse>(
      commandSyncPutRawChange,
      request,
    );
  }
}

Timestamp? parseTimestamp(String? timestamp) {
  if (timestamp == null) {
    return null;
  }
  return Timestamp.tryParse(timestamp);
}

SyncedDataSourceRef apiChangeRefToRecordRef(ApiChangeRef change) {
  return SyncedDataSourceRef(
    syncId: change.syncId.v,
    key: change.key.v,
    store: change.store.v,
  );
}

void recordRefToSyncChangeRef(SyncedDataSourceRef record, ApiChangeRef change) {
  change
    ..syncId.v = record.syncId
    ..store.v = record.store
    ..key.v = record.key;
}

void recordToSyncChangeRef(CvSyncedSourceRecord record, ApiChangeRef change) {
  var recordData = record.record.v!;
  change
    ..syncId.v = record.syncId.v
    ..store.v = recordData.store.v
    ..key.v = recordData.key.v;
}

CvSyncedSourceRecord apiChangeToRecord(ApiChange change) {
  var recordData =
      CvSyncedSourceRecordData()
        ..store.v = change.store.v
        ..key.v = change.key.v
        ..value.v = jsonDecodeSembastValueOrNull(change.data.v) as Model?
        ..deleted.v = change.data.v == null;
  return CvSyncedSourceRecord()
    ..syncId.v = change.syncId.v
    ..syncChangeId.v = change.changeNum.v
    ..syncTimestamp.v = parseTimestamp(change.timestamp.v)
    ..record.v = recordData;
}

void recordToSyncChange(CvSyncedSourceRecord record, ApiChange change) {
  recordToSyncChangeRef(record, change);
  var recordData = record.record.v!;
  change
    ..changeNum.v = record.syncChangeId.v
    ..data.v = jsonEncodeSembastValueOrNull(recordData.value.v) as Model?
    ..timestamp.v = record.syncTimestamp.v?.toIso8601String();
}

CvMetaInfoRecord syncInfoToMeta(ApiSyncInfo info) {
  return CvMetaInfoRecordApi()
    ..version.setValue(info.version.v)
    ..minIncrementalChangeId.setValue(info.minIncrementalChangeNum.v)
    ..lastChangeId.setValue(info.lastChangeNum.v);
}

void metaToSyncInfo(CvMetaInfoRecord meta, ApiSyncInfo info) {
  info
    ..lastChangeNum.setValue(meta.lastChangeId.v)
    ..minIncrementalChangeNum.setValue(meta.minIncrementalChangeId.v)
    ..version.setValue(meta.version.v);
}
