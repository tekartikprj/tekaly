import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

void initFsBuilders() {
  cvAddConstructors([FsApp.new, FsAppInfo.new, FsNoNameAppInfo.new]);
  cvAddConstructors([CvAppInfoSub1.new, CvAppInfoSub2.new]);
}

class FsApp extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');
  @override
  CvFields get fields => [name];
}

class CvAppInfoSub1 extends CvModelBase {
  final sub1 = CvField<String>('sub1');
  @override
  CvFields get fields => [sub1];
}

class CvAppInfoSub2 extends CvModelBase {
  final sub2 = CvField<String>('sub2');
  @override
  CvFields get fields => [sub2];
}

class CvAppInfoNoNameSub1 extends CvModelBase {
  final sub1 = CvField<String>('sub1');
  @override
  CvFields get fields => [sub1];
}

class CvAppInfoNoNameSub2 extends CvModelBase {
  final sub2 = CvField<String>('sub2');
  @override
  CvFields get fields => [sub2];
}

class FsAppInfo extends CvFirestoreDocumentBase {
  final stringList = CvListField<String>('stringList');
  final name = CvField<String>('name');
  final sub1 = CvModelField<CvAppInfoSub1>('sub1');
  final sub2s = CvModelListField<CvAppInfoSub2>('sub2s');
  final noNameSub1 = CvModelField<CvAppInfoNoNameSub1>('noNameSub1');
  final noNameSub2s = CvModelListField<CvAppInfoNoNameSub2>('noNameSub2s');
  @override
  CvFields get fields => [
    name,
    sub1,
    sub2s,
    noNameSub1,
    noNameSub2s,
    stringList,
  ];
}

class FsNoNameAppInfo extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');
  @override
  CvFields get fields => [name];
}
