// ignore_for_file: depend_on_referenced_packages

/*import 'package:dcjo2023_common/constant.dart';

import 'package:dcjo2023_ff/constant.dart';
import 'package:dcjo2023_ff/src/functions.dart';
import 'package:dcjo2023_ff/src/proxy_request.dart';

 */
//import 'package:tekartik_app_http/app_http.dart';

import 'package:cv/cv_json.dart';
//import 'package:tekartik_firebase_functions_node/firebase_functions_universal.dart';
/*
import 'firebase_universal.dart';
import 'import.dart';
import 'model/info_response.dart';

 */
import 'package:tekartik_firebase_firestore/firestore.dart';
import 'package:tekartik_firebase_functions/firebase_functions.dart';
import 'package:tekartik_http/http.dart';
import 'package:tekaly_sembast_synced/src/api/model/api_error.dart';
import 'package:tekaly_sembast_synced/src/api/model/api_models.dart';
import 'package:tekaly_sembast_synced/src/api/model/api_sync.dart';
import 'package:tekaly_sembast_synced/src/api/sync_api.dart';
import 'package:tekaly_sembast_synced/src/api/synced_source_api.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
import 'package:tekaly_sembast_synced/src/firebase/model/fs_models.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_source_firestore.dart';

import '../sync/model/source_meta_info.dart';

Model bodyAsMap(ExpressHttpRequest request) {
  return requestBodyAsJsonObject(request.body)!;
}

var _builderInitialized = false;

void initBuilders() {
  if (!_builderInitialized) {
    _builderInitialized = true;

    initApiBuilders();
    initFsBuilders();
  }
}

class FfServerApp {
  final AppFirebaseContext appFirebaseContext;

  FirebaseContext get firebaseContext => appFirebaseContext.firebaseContext;

  FirebaseFunctions get functions => firebaseContext.functions!;

  String get app => appFirebaseContext.app;
  var instanceCallCount = 0;
  final bool isLocal;

  Firestore get firestore => firebaseContext.firestore;

  FfServerApp({
    required this.appFirebaseContext,
    this.isLocal = false,
  }) {
    initApiBuilders();
  }

  HttpsFunction get commandV1 => functions.https.onRequestV2(
      HttpsOptions(cors: true, region: regionBelgium), commandHttp);

  Future<void> commandHttp(ExpressHttpRequest request) async {
    var uri = request.uri;
    try {
      if (uri.pathSegments.isNotEmpty) {
        var command = uri.pathSegments.last;
        switch (command) {
          /*case commandProxy:
            await proxyExpressHttpRequest(request);
            return;*/

          case commandSyncGetInfo:
            await SyncGetInfoCommandHandler(
              request: request,
              appFirebaseContext: appFirebaseContext,
            ).handle();
            return;
          case commandSyncGetChanges:
            await SyncGetChangesCommandHandler(
              request: request,
              appFirebaseContext: appFirebaseContext,
            ).handle();
            return;
          case commandSyncPutChange:
            await SyncPutChangeCommandHandler(
              request: request,
              appFirebaseContext: appFirebaseContext,
            ).handle();
            return;
          case commandSyncPutRawChange:
            await SyncPutRawChangeCommandHandler(
              request: request,
              appFirebaseContext: appFirebaseContext,
            ).handle();
            return;
          case commandSyncGetChange:
            await SyncGetChangeCommandHandler(
              request: request,
              appFirebaseContext: appFirebaseContext,
            ).handle();
            return;
          case commandSyncPutInfo:
            await SyncPutInfoCommandHandler(
              request: request,
              appFirebaseContext: appFirebaseContext,
            ).handle();
            return;
        }
      }
      throw UnsupportedError('Unsupported command $uri');
    } catch (e, st) {
      // devPrint(st);

      await sendErrorResponse(
          request,
          httpStatusCodeInternalServerError,
          ApiErrorResponse()
            ..message.v = e.toString()
            ..stackTrace.v = st.toString());
    }
  }

  Future<void> sendResponse(ExpressHttpRequest request, CvModel model) async {
    var res = request.response;
    res.headers.set(httpHeaderContentType, httpContentTypeJson);
    await res.send(model.toMap());
  }

  Future<void> sendErrorResponse(
      ExpressHttpRequest request, int statusCode, CvModel model) async {
    var res = request.response;
    try {
      res.statusCode = statusCode;
      res.headers.set(httpHeaderContentType, httpContentTypeJson);
    } catch (_) {}

    await res.send(model.toMap());
  }

  void initFunction(String name) {
    functions[name] = commandV1;
  }
}

class CommandHandler {
  final ExpressHttpRequest request;

  Future<void> sendErrorResponse(int statusCode, CvModel model) async {
    var res = request.response;
    res.statusCode = statusCode;
    res.headers.set(httpHeaderContentType, httpContentTypeJson);
    await res.send(model.toMap());
  }

  CommandHandler({required this.request}) {
    initBuilders();
  }

  Future<void> sendResponse(ExpressHttpRequest request, CvModel model) async {
    var res = request.response;
    res.headers.set(httpHeaderContentType, httpContentTypeJson);
    await res.send(model.toJson());
  }
}

abstract class SyncCommandHandler extends FirebaseCommandHandler {
  SyncCommandHandler(
      {required super.request, required super.appFirebaseContext});

  Future<bool> requireTargetAuthToken(String target) async {
    // Or send error
    return true;
  }
}

abstract class FirebaseCommandHandler extends CommandHandler {
  late SyncedSourceFirestore syncedSourceFirestore;

  String get app => appFirebaseContext.app;
  final AppFirebaseContext appFirebaseContext;
  Firestore get firestore => firebaseContext.firestore;
  FirebaseContext get firebaseContext => appFirebaseContext.firebaseContext;

  void initSyncSource(String target) {
    syncedSourceFirestore = SyncedSourceFirestore(
      firestore: firebaseContext.firestore,
      rootPath: fsAppSyncPath(app, target),
    );
  }

  FirebaseCommandHandler({
    required super.request,
    required this.appFirebaseContext,
  });

  Future<CvMetaInfoRecord> getMetaInfo() async {
    var metaInfo = await syncedSourceFirestore.getMetaInfo();
    return metaInfo ?? CvMetaInfoRecord();
  }
}

class SyncGetInfoCommandHandler extends SyncCommandHandler {
  SyncGetInfoCommandHandler({
    required super.request,
    required super.appFirebaseContext,
  });

  Future<void> handle() async {
    var apiRequest = bodyAsMap(request).cv<ApiGetSyncInfoRequest>();
    var target = apiRequest.target.v!;
    initSyncSource(target);

    var meta =
        (await syncedSourceFirestore.getMetaInfo()) ?? CvMetaInfoRecord();
    var response = ApiGetSyncInfoResponse();
    metaToSyncInfo(meta, response);
    await sendResponse(request, response);
  }
}

class SyncPutInfoCommandHandler extends SyncCommandHandler {
  SyncPutInfoCommandHandler({
    required super.request,
    required super.appFirebaseContext,
  });

  Future<void> handle() async {
    var apiRequest = bodyAsMap(request).cv<ApiPutSyncInfoRequest>();
    var target = apiRequest.target.v!;
    if (await requireTargetAuthToken(target)) {
      initSyncSource(target);

      var metaInfo = syncInfoToMeta(apiRequest);
      var meta = (await syncedSourceFirestore.putMetaInfo(metaInfo)) ??
          CvMetaInfoRecord();
      var response = ApiPutSyncInfoResponse();
      metaToSyncInfo(meta, response);
      await sendResponse(request, response);
    }
  }
}

class SyncGetChangesCommandHandler extends SyncCommandHandler {
  SyncGetChangesCommandHandler({
    required super.request,
    required super.appFirebaseContext,
  });

  Future<void> handle() async {
    var apiRequest = bodyAsMap(request).cv<ApiGetChangesRequest>();
    var target = apiRequest.target.v!;
    if (await requireTargetAuthToken(target)) {
      initSyncSource(target);

      var recordList = await syncedSourceFirestore.getSourceRecordList(
          afterChangeId: apiRequest.afterChangeNum.v,
          includeDeleted: apiRequest.includeDeleted.v,
          limit: apiRequest.limit.v);

      var metaInfo = await getMetaInfo();

      var syncInfo = ApiSyncInfo();
      metaToSyncInfo(metaInfo, syncInfo);
      var response = ApiGetChangesResponse()
        ..syncInfo.v = syncInfo
        ..lastChangeNum.v = recordList.lastChangeId
        ..changes.v = recordList.list.map((e) {
          var apiChange = ApiChange();
          recordToSyncChange(e, apiChange);
          return apiChange;
        }).toList();
      if (recordList.isNotEmpty) {
        response.lastChangeNum.v = response.changes.v!.last.changeNum.v;
      }
      await sendResponse(request, response);
    }
  }
}

class SyncGetChangeCommandHandler extends SyncCommandHandler {
  SyncGetChangeCommandHandler({
    required super.request,
    required super.appFirebaseContext,
  });

  Future<void> handle() async {
    var apiRequest = bodyAsMap(request).cv<ApiGetChangeRequest>();
    var target = apiRequest.target.v!;
    if (await requireTargetAuthToken(target)) {
      initSyncSource(target);

      var ref = apiChangeRefToRecordRef(apiRequest);
      var record = await syncedSourceFirestore.getSourceRecord(ref);

      var metaInfo = await getMetaInfo();

      var syncInfo = ApiSyncInfo();
      metaToSyncInfo(metaInfo, syncInfo);
      var response = ApiGetChangeResponse();
      if (record != null) {
        recordToSyncChange(record, response);
      }
      await sendResponse(request, response);
    }
  }
}

class SyncPutChangeCommandHandler extends SyncCommandHandler {
  SyncPutChangeCommandHandler({
    required super.request,
    required super.appFirebaseContext,
  });

  Future<void> handle() async {
    var apiRequest = bodyAsMap(request).cv<ApiPutChangeRequest>();
    var target = apiRequest.target.v!;
    if (await requireTargetAuthToken(target)) {
      initSyncSource(target);

      var record = apiChangeToRecord(apiRequest);
      var newRecord = await syncedSourceFirestore.putSourceRecord(record);
      var response = ApiPutChangeResponse();

      if (newRecord != null) {
        recordToSyncChange(newRecord, response);
      }
      await sendResponse(request, response);
    }
  }
}

class SyncPutRawChangeCommandHandler extends SyncCommandHandler {
  SyncPutRawChangeCommandHandler({
    required super.request,
    required super.appFirebaseContext,
  });

  Future<void> handle() async {
    var apiRequest = bodyAsMap(request).cv<ApiPutChangeRequest>();
    var target = apiRequest.target.v!;
    if (await requireTargetAuthToken(target)) {
      initSyncSource(target);

      var record = apiChangeToRecord(apiRequest);
      // ignore: invalid_use_of_visible_for_testing_member
      await syncedSourceFirestore.putRawRecord(record);
      var response = ApiPutChangeResponse();
      await sendResponse(request, response);
    }
  }
}
