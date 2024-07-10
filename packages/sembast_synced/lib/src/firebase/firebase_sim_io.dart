import 'package:tekartik_firebase_firestore_sembast/firestore_sembast_io.dart';
// ignore: depend_on_referenced_packages
import 'package:tekartik_firebase_local/firebase_local.dart';

import 'firebase.dart';

FirebaseContext initFirebaseSimIo() {
  isFirebaseSim = true;

  var firebase = FirebaseLocal();
  var servicesContext = FirebaseServicesContext(
      firebase: firebase, firestore: firestoreServiceIo);
  return servicesContext.initServices();
  /*
  firestoreService = firestoreServiceIo;
  authService = authServiceLocal;
  storageService =
      createStorageServiceIo(basePath: join('.local', 'firebase', 'storage'));

   */
}
