// ignore_for_file: avoid_print

import 'package:tekaly_sembast_synced/synced_db_firestore.dart';
import 'package:tekartik_firebase_firestore/firestore_logger.dart' as fb;
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart'
    as fb;

var _debugFirestore = false;
// var debugFirestore = devTrue;
SyncedSourceFirestore newInMemorySyncedSourceFirestore() {
  fb.Firestore firestore;
  SyncedSourceFirestore source;

  firestore = fb.newFirestoreMemory();
  if (_debugFirestore) {
    firestore = fb.FirestoreLogger(
      firestore: firestore,
      options: fb.FirestoreLoggerOptions.all(
        log: (event) {
          print(event);
        },
      ),
    );
  }
  source = SyncedSourceFirestore(firestore: firestore, rootPath: null);
  return source;
}
