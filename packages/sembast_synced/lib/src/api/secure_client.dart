import 'package:cv/cv_json.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:path/path.dart';
import 'package:tekaly_sembast_synced/src/firebase/firebase.dart';
// ignore_for_file: depend_on_referenced_packages

import 'package:tekaly_sembast_synced/src/firebase/firebase_sim.dart';
import 'package:tekaly_sembast_synced/src/server/server_app.dart';
import 'package:tekartik_app_http/app_http.dart' as universal;
import 'package:tekartik_firebase_firestore/firestore.dart';
import 'package:tekartik_firebase_functions_http/ff_server.dart';
import 'package:tekartik_firebase_functions_http/firebase_functions_memory.dart';
import 'package:tekartik_http/http_client.dart';

import 'import_common.dart';
import 'model/api_error.dart';
import 'model/api_models.dart';

FirestoreService? appServiceFirestoreService;
Firestore? appServiceFirestore;

// Only started once
FfServerHttp? ffServerHttp;

var debugWebServices = false; // devWarning(true);

class ApiException implements Exception {
  final ApiErrorResponse? errorResponse;
  final int? statusCode;
  late final String? message;
  final Object? cause;

  ApiException(
      {this.statusCode, String? message, this.cause, this.errorResponse}) {
    this.message = message ?? errorResponse?.message.v;
  }

  @override
  String toString() {
    var sb = StringBuffer();
    if (statusCode != null) {
      sb.write(statusCode);
    }
    if (message != null) {
      if (sb.isNotEmpty) {
        sb.write(': ');
      }
      sb.write(message.toString());
    }

    return 'ApiException($sb)${errorResponse != null ? ': $errorResponse' : ''}';
  }
}

abstract interface class ApiService {
  Future<T> send<T extends CvModel>(String command, CvModel request);
}

class SecureApiServiceBase implements ApiService {
  final String app;

  final String appType;
  late Uri commandUri;
  final bool isLocal;
  late Client client;
  Client get secureClient => client;
  var retryCount = 0;
  final String functionName;
  final String packageName;

  SecureApiServiceBase({
    required this.functionName,

    /// For the simulation storage
    required this.packageName,
    required this.app,
    required this.appType,

    /// For the real server, functionName will be appended
    Uri? commandUri,
    this.isLocal = false,
  }) {
    initApiBuilders();
    if (commandUri != null) {
      this.commandUri = commandUri;
    }
  }

  String uniqueAppName([String name = '']) {
    var prefix = '$appType-$app';
    if (isLocal) {
      prefix = '$prefix-local';
    }
    name = '$prefix${name.isNotEmpty ? '-$name' : ''}';

    return name;
  }

  void log(String message) {
    // ignore: avoid_print
    print(message);
  }

  Future<void> initClient() async {
    late HttpClientFactory httpClientFactory;
    if (isLocal) {
      firebaseSimContext ??= initFirebaseSim(packageName: packageName);

      // User firestore for sync
      appServiceFirestoreService = firebaseSimContext?.services.firestore;
      appServiceFirestore = firebaseSimContext?.firestore;

      httpClientFactory = httpClientFactoryMemory;
      var ff = firebaseFunctionsMemory;
      var ffServerApp = FfServerApp(
          appFirebaseContext: AppFirebaseContext(
              firebaseContext: firebaseSimContext!, app: app),
          isLocal: true);
      ffServerApp.initFunction(functionName);
      if (ffServerHttp == null) {
        var httpServer = await ff.serveHttp();
        var ffServer = FfServerHttp(httpServer);
        ffServerHttp = ffServer;
      }

      commandUri = ffServerHttp!.uri.replace(path: functionName);

      // Start server
    } else {
      httpClientFactory = universal.httpClientFactoryUniversal;

      commandUri = commandUri.replace(path: functionName);
    }
    var innerClient = httpClientFactory.newClient();
    client = RetryClient(innerClient, when: (response) {
      if (universal.isHttpStatusCodeSuccessful(response.statusCode)) {
        return false;
      }
      switch (response.statusCode) {
        case universal.httpStatusCodeForbidden:
        case universal.httpStatusCodeUnauthorized:
          return false;
      }
      retryCount++;
      print('retry: ${response.statusCode}');
      return true;
    }, whenError: (error, stackTrace) {
      print('retry error?: error');
      print(error);
      print(stackTrace);
      return true;
    });
  }

  Uri getUri(String command) {
    return commandUri.replace(path: url.join(commandUri.path, command));
  }

  @override
  Future<T> send<T extends CvModel>(String command, CvModel request) async {
    try {
      var response = await clientSend<T>(secureClient, command, request);
      if (response.isSuccessful) {
        return response.data!;
      } else {
        throw ApiException(
            message: '${response.error?.message}',
            statusCode: response.statusCode,
            cause: response.error);
      }
    } catch (e, st) {
      if (isDebug) {
        print(e);
        print(st);
      }
      if (e is ApiException) {
        rethrow;
      } else {
        throw ApiException(message: '$e', cause: e);
      }
    }
  }

  Future<ServiceResponse<T>> clientSend<T extends CvModel>(
      Client client, String command, CvModel request,
      {Map<String, String>? additionalHeaders}) async {
    var uri = getUri(command);
    if (debugWebServices) {
      log('-> uri: $uri');
      log('   $request');
    }
    // devPrint('uri $uri');
    var headers = <String, String>{
      httpHeaderContentType: httpContentTypeJson,
      httpHeaderAccept: httpContentTypeJson
    };
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
    }
    // devPrint('query headers: $headers');
    var response = await httpClientSend(client, httpMethodPost, uri,
        headers: headers, body: utf8.encode(jsonEncode(request.toMap())));
    //devPrint('response headers: ${response.headers}');
    response.body;
    var body = utf8.decode(response.bodyBytes);
    var statusCode = response.statusCode;
    // Only reply with a token if we have one
    /*
    TokenInfo? tokenInfo;

    var responseToken = response.headers.value(tokenHeader);
    if (responseToken != null) {
      tokenInfo = TokenInfo.fromToken(responseToken);
      if (tokenInfo == null) {
        throw ArgumentError('invalid token $responseToken');
      } else {
        if (tokenInfo.clientDateTime.difference(DateTime.timestamp()).abs() >
            const Duration(hours: 6)) {
          throw ArgumentError('invalid client token $responseToken');
        }
      }
    }*/
    if (debugWebServices) {
      log('<- $statusCode $body');
    }
    // Save token
    /*if (tokenInfo != null) {
      lastTokenInfo = tokenInfo;
    }*/
    if (response.isSuccessful) {
      return ServiceResponse(
        statusCode: response.statusCode,
        data: body.cv<T>(),
      );
    } else {
      ApiErrorResponse? errorResponse;
      try {
        errorResponse = body.cv<ApiErrorResponse>();
      } catch (e) {
        print(e);
      }
      return ServiceResponse(
        statusCode: response.statusCode,
        error: errorResponse,
      );
    }
  }

  /*
  Future<void> syncMemory(String siteId) async {
    var target = getSiteTarget(siteId);
    var dbName = getTargetDbName(target);
    var siteDb = SyncedDb(
        databaseFactory: databaseFactoryMemory,
        syncedStoreNames: [dbUserStoreRef.name],
        name: uniqueAppName(dbName));

    var source = SyncedSourceApi(apiService: this, target: target);
    var sync = SyncedDbSourceSync(db: siteDb, source: source);
    await sync.sync();
  }*/
}

class ServiceResponse<T extends CvModel> {
  T? data;
  int statusCode;
  ApiErrorResponse? error;
  bool get isSuccessful => data != null;

  ServiceResponse({
    required this.statusCode,
    this.data,
    this.error,
  });
}
