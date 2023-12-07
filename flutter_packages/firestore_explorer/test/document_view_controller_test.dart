import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekaly_firestore_explorer/src/import_firebase.dart';

import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

class FsRootCollectionDoc extends CvFirestoreDocumentBase {
  final value = CvField<int>('value');
  @override
  CvFields get fields => [value];
}

Future<void> main() async {
  late Firestore firestore;
  group('view controller', () {
    setUp(() {
      firestore = newFirestoreMemory();
    });

    test('controller', () async {
      var coll = CvCollectionReference<FsRootCollectionDoc>('root');
      var doc = coll.doc('1');

      var controller = FsDocumentViewController<FsRootCollectionDoc>(
          firestore: firestore, docRef: doc);

      controller.close();
    });
  });
}
