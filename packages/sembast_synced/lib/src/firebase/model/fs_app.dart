import 'package:tekaly_sembast_synced/src/firebase/import_firebase.dart';

class FsApp extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');

  @override
  late final fields = <CvField>[name];
}

final fsAppModel = FsApp();
