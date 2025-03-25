import 'package:tekaly_sembast_synced/synced_db_internals.dart';
import 'package:tkcms_common/tkcms_api.dart';

/// Init needed builders
void initSembastSyncedRpcBuilders() {
  cvAddConstructors([
    PutSourceRecordApiQuery.new,
    PutSourceRecordApiResult.new,
    GetSourceRecordApiQuery.new,
    ApiError.new,
    ApiRequest.new,
    ApiResponse.new,
    GetSourceRecordListApiQuery.new,
    GetSourceRecordListApiResult.new,
    GetMetaInfoApiResult.new,
    PutMetaInfoApiQuery.new,
    CvMetaInfo.new,
  ]);
}

/// The rpc service name for the synced source
const syncedSourceRpcServiceName = 'synced_source';

/// Put a source record
const requestPutSourceRecordCommand = 'put_source_record';

/// Get a source record
const requestGetSourceRecordCommand = 'get_source_record';

/// Get a source record list
const requestGetSourceRecordListCommand = 'get_source_record_list';

/// Get meta_info record
const requestGetMetaInfoCommand = 'get_meta_info';

/// Put meta_info record
const requestPutMetaInfoCommand = 'put_meta_info';

/// Get meta_info record
const requestGetMetaInfoChangedCommand = 'get_meta_info_changed';

/// Put a source record
class PutSourceRecordApiQuery extends ApiQuery {
  /// The record (CvSyncedSourceRecord json encoded)
  final record = CvModelField<CvMapModel>('record');

  @override
  CvFields get fields => [record];
}

/// Put a source record
class PutSourceRecordApiResult extends ApiResult {
  /// The record (CvSyncedSourceRecord json encoded)
  final record = CvModelField<CvMapModel>('record');

  @override
  CvFields get fields => [record];
}

/// Get a source record
class GetSourceRecordApiQuery extends ApiQuery {
  /// The sync id (compat)
  final syncId = CvField<String>('syncId');

  /// Store
  final store = CvField<String>('store');

  /// Key
  final key = CvField<String>('key');

  @override
  CvFields get fields => [syncId, store, key];
}

/// For get, record can be null
typedef GetSourceRecordApiResult = PutSourceRecordApiResult;

/// Get a source record list query
class GetSourceRecordListApiQuery extends ApiQuery {
  /// After changed id
  final afterChangeId = CvField<int>('afterChangeId');

  /// limit
  final limit = CvField<int>('limit');

  /// Key
  final includeDeleted = CvField<bool>('includeDeleted');

  @override
  CvFields get fields => [afterChangeId, limit, includeDeleted];
}

/// Get a source record list result
class GetSourceRecordListApiResult extends ApiResult {
  /// After changed id
  final lastChangeId = CvField<int>('lastChangeId');

  /// The records (CvSyncedSourceRecord json encoded)
  final records = CvModelListField<CvMapModel>('records');

  @override
  CvFields get fields => [lastChangeId, records];
}

/// Get meta info record result
class GetMetaInfoApiResult extends ApiResult {
  /// The meta info
  final metaInfo = CvModelField<CvMetaInfo>('metaInfo');
  @override
  CvFields get fields => [metaInfo];
}

/// Putt meta info record query
class PutMetaInfoApiQuery extends ApiQuery with CvMetaInfoMixin {
  /// The meta info
  final metaInfo = CvModelField<CvMetaInfo>('metaInfo');
  @override
  CvFields get fields => [metaInfo];
}

/// meta info is not null here
typedef PutMetaInfoApiResult = GetMetaInfoApiResult;

/// On changed meta info
typedef GetMetaInfoApiChangedQuery = PutMetaInfoApiQuery;

/// On changed meta info
typedef GetMetaInfoApiChangedResult = GetMetaInfoApiResult;
