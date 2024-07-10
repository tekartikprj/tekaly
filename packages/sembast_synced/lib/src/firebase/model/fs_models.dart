import 'package:tekaly_sembast_synced/src/firebase/import_firebase.dart';

import 'fs_app.dart';
import 'fs_export.dart';

void initFsBuilders() {
  cvAddConstructor(FsApp.new);
  cvAddConstructor(FsExport.new);
}

CvDocumentReference<FsApp> dbAppRoot(String app) =>
    CvDocumentReference<FsApp>('app/$app');

String fsAppSyncPath(String app, String target) =>
    '${dbAppRoot(app).path}/sync/$target';
