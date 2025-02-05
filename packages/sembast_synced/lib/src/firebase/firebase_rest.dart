import 'package:http/http.dart';
import 'package:tekartik_firebase_firestore_rest/firestore_rest.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_firebase_rest/firebase_rest.dart';
import 'package:tekartik_firebase_storage_rest/storage_json.dart';

import 'firebase.dart';

FirebaseContext initFirebaseRest(Client client, {required String fbProjectId}) {
  var firebase = firebaseRest;
  var firestoreService = firestoreServiceRest;
  var app = firebase.initializeApp(
      options: AppOptionsRest(client: client)..projectId = fbProjectId);
  var firestore = firestoreServiceRest.firestore(app);
  var servicesContext =
      FirebaseServicesContext(firebase: firebase, firestore: firestoreService);
  return FirebaseContext(services: servicesContext, firestore: firestore);
  // authService = authServiceRest;
  //storageService = storageServiceRest;
}

/// Import using the rest storage api
class SyncedDbUnauthenticatedStorageApiImportContext {
  /// Storage api
  final UnauthenticatedStorageApi storageApi;

  /// Root path (typically `project/<projectId>/data`)
  final String rootPath;

  /// Optional meta basename suffix
  final String? metaBasenameSuffix;

  /// Context
  SyncedDbUnauthenticatedStorageApiImportContext(
      {required this.storageApi,
      required this.rootPath,
      this.metaBasenameSuffix});
}
