import 'package:tekaly_sembast_synced/src/firebase/import_firebase.dart';

//
class FsExport extends CvFirestoreDocumentBase {
  final timestamp = CvField<Timestamp>('timestamp');
  final version = CvField<int>('version');
  final changeNum = CvField<int>('changeNum');
  // Informative, using \n as line feed, might differ on windows io
  final size = CvField<int>('size');

  @override
  List<CvField> get fields => [version, timestamp, changeNum, size];
}

final fsExportModel = FsExport();
