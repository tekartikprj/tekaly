// ignore_for_file: provide_deprecation_message

import 'package:tekartik_firebase_functions/firebase_functions.dart';

import 'import_firebase.dart';

// Globals for anim app and server.
/// Whether the package is using the Firebase simulator implementation.
var isFirebaseSim = false;
//@deprecated
//late Firestore firestore;

/// Shared Firebase service factories used to build application contexts.
class FirebaseServicesContext {
  /// Firestore service factory.
  final FirestoreService firestore;

  /// Firebase app factory.
  final Firebase firebase;

  /// Creates the services context.
  FirebaseServicesContext({required this.firebase, required this.firestore});

  /// Initializes a Firebase app and returns the bound runtime context.
  FirebaseContext initServices() {
    var firebaseApp = firebase.initializeApp();
    return FirebaseContext(
      services: this,
      firestore: firestore.firestore(firebaseApp),
    );
  }
}

/// Runtime Firebase context bound to an initialized app.
class FirebaseContext {
  /// Services used to build this context.
  final FirebaseServicesContext services;

  /// Firestore instance for the initialized app.
  final Firestore firestore;

  /// Optional Cloud Functions client.
  FirebaseFunctions? functions;

  /// Creates the Firebase runtime context.
  FirebaseContext({
    required this.services,
    this.functions,
    required this.firestore,
  });
}

/// Firebase context associated with a logical application name.
class AppFirebaseContext {
  /// Backing Firebase context.
  final FirebaseContext firebaseContext;

  /// Application name.
  final String app;

  /// Creates the application Firebase context.
  AppFirebaseContext({required this.firebaseContext, required this.app});
}

/// Simulator Firebase context, when one is configured.
FirebaseContext? firebaseSimContext;

/// Active Firebase context, when one is configured.
FirebaseContext? firebaseContextOrNull;

/// Active Firebase context.
FirebaseContext get firebaseContext => firebaseContextOrNull!;

/// Marker interface for storage import contexts.
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

  /// Creates the storage import/export context.
  SyncedDbStorageImportExportContext({
    required this.storage,
    this.bucketName,
    required this.rootPath,
    this.metaBasenameSuffix,
  });
}
