// ignore: depend_on_referenced_packages

/*

@visibleForTesting
Future<FirebaseContext> initFirebaseIoWithServiceAccount() async {
  //initFirebaseIo();
  var firebaseAdmin = firebaseRest as FirebaseAdmin;
  firebaseAdmin.credential
      .setApplicationDefault(FirebaseAdminCredentialRest.fromServiceAccountJson(
    serviceAccountJsonString,
    //    scopes: scopes
  ));
  await firebaseAdmin.credential.applicationDefault()?.getAccessToken();
  return FirebaseServicesContext(
          firebase: firebaseAdmin, firestore: firestoreServiceRest)
      .initServices();
}
*/
