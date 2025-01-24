// ignore_for_file: provide_deprecation_message

import 'package:tekartik_firebase_functions/firebase_functions.dart';

import 'import_firebase.dart';

// Globals for anim app and server.
var isFirebaseSim = false;
//@deprecated
//late Firestore firestore;

class FirebaseServicesContext {
  final FirestoreService firestore;
  final Firebase firebase;

  FirebaseServicesContext({required this.firebase, required this.firestore});

  FirebaseContext initServices() {
    var firebaseApp = firebase.initializeApp();
    return FirebaseContext(
        services: this, firestore: firestore.firestore(firebaseApp));
  }
}

class FirebaseContext {
  final FirebaseServicesContext services;
  final Firestore firestore;
  FirebaseFunctions? functions;

  FirebaseContext(
      {required this.services, this.functions, required this.firestore});
}

class AppFirebaseContext {
  final FirebaseContext firebaseContext;
  final String app;

  AppFirebaseContext({required this.firebaseContext, required this.app});
}

FirebaseContext? firebaseSimContext;
FirebaseContext? firebaseContextOrNull;
FirebaseContext get firebaseContext => firebaseContextOrNull!;

class SyncedDbStorageImportContext {}

/// Export context
typedef SyncedDbStorageExportContext = SyncedDbStorageImportExportContext;

/// Context for importing data from storage
class SyncedDbStorageImportExportContext
    implements SyncedDbStorageImportContext {
  /// Storage
  final FirebaseStorage storage;

  /// Optional bucket name
  final String? bucketName;

  /// Root path
  final String rootPath;

  /// Optional meta basename suffix
  final String? metaBasenameSuffix;

  /// Constructor
  SyncedDbStorageImportExportContext(
      {required this.storage,
      this.bucketName,
      required this.rootPath,
      this.metaBasenameSuffix});
}
