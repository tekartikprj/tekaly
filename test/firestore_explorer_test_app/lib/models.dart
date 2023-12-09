import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

void initFsBuilders() {
  cvAddConstructors([FsApp.new]);
}

class FsApp extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');
  @override
  CvFields get fields => [name];
}
