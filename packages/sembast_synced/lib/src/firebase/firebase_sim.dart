import 'package:tekartik_app_sembast/sembast.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';
import 'package:tekartik_firebase_functions_http/firebase_functions_memory.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_firebase_local/firebase_local.dart';

import 'firebase.dart';

FirebaseContext initFirebaseSimMemory() {
  isFirebaseSim = true;
  var firebase = FirebaseLocal();
  var firestoreService = newFirestoreServiceMemory();

  return FirebaseServicesContext(
          firebase: firebase, firestore: firestoreService)
      .initServices()
    ..functions = firebaseFunctionsMemory;
}

FirebaseContext initFirebaseSim({required String packageName}) {
  isFirebaseSim = true;
  var firebase = FirebaseLocal();
  var sembastDatabaseFactory = getDatabaseFactory(packageName: packageName);
  var firestoreService = FirestoreServiceSembast(sembastDatabaseFactory);
  return FirebaseServicesContext(
          firebase: firebase, firestore: firestoreService)
      .initServices()
    ..functions = firebaseFunctionsMemory;
}
