import 'package:tkcms_common/tkcms_api.dart';

/// The rpc service name for the synced source
const syncedSourceRpcServiceName = 'synced_source';

/// Put a source record
const requestPutSourceRecordCommand = 'put_source_record';

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
