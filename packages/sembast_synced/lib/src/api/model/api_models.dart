import 'package:cv/cv.dart';
import 'package:tekaly_sembast_synced/src/api/model/api_error.dart';

import 'api_sync.dart';

/// Init api builder
void initApiBuilders() {
  cvAddConstructor(ApiChange.new);
  cvAddConstructor(ApiErrorResponse.new);
  cvAddConstructor(ApiGetChangesRequest.new);
  cvAddConstructor(ApiGetChangesResponse.new);
  cvAddConstructor(ApiGetChangeRequest.new);
  cvAddConstructor(ApiGetChangeResponse.new);
  cvAddConstructor(ApiPutChangeRequest.new);
  cvAddConstructor(ApiPutChangeResponse.new);
  cvAddConstructor(ApiPutChangesRequest.new);
  cvAddConstructor(ApiPutChangesResponse.new);
  cvAddConstructor(ApiSyncInfo.new);
  cvAddConstructor(ApiGetSyncInfoRequest.new);
  cvAddConstructor(ApiGetSyncInfoResponse.new);
  cvAddConstructor(ApiPutSyncInfoRequest.new);
  cvAddConstructor(ApiPutSyncInfoResponse.new);
}
