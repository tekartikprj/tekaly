import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekaly_firestore_explorer/src/mapping.dart';

final _apps = CvCollectionReference<_App>('apps');
final _app1 = _apps.doc('1');
final _infos = _apps.any.collection<CvFirestoreDocument>('infos');
final _appInfo1 = _infos.cast<_AppInfo>().doc('app');

class _AppInfo extends CvFirestoreDocumentBase {
  final value = CvField<int>('value');
  @override
  CvFields get fields => [value];
}

class _App extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');
  @override
  CvFields get fields => [name];
}

Future<void> main() async {
  documentViewInit();
  cvAddConstructors([_App.new, _AppInfo.new]);
  group('documentView data', () {
    setUp(() {
      documentViewClearData();
    });
    test('data coll', () async {
      documentViewAddCollections([_apps]);
      var ref = documentViewGetDocument('apps/1');
      expect(ref.cv(), isA<_App>());
      expect(documentViewGetDocument('apps/1').path, 'apps/1');
    });
    test('data doc', () async {
      documentViewAddDocuments([_app1, _appInfo1]);
      var ref = documentViewGetDocument('apps/1');
      expect(ref.cv(), isA<_App>());
      expect(documentViewGetDocument('apps/1').path, 'apps/1');

      ref = documentViewGetDocument('apps/app1/infos/app');
      expect(ref.cv(), isA<_AppInfo>());
      expect(ref.path, 'apps/app1/infos/app');

      ref = documentViewGetDocument('apps/app1/infos/dummy');
      expect(ref.cv(), isA<CvFirestoreMapDocument>());
    });

    test('data doc 2', () async {
      documentViewAddCollections([_infos]);
      documentViewAddDocuments([_app1, _appInfo1]);

      var ref = documentViewGetDocument('apps/app1/infos/app');
      expect(ref.cv(), isA<_AppInfo>());
      expect(ref.path, 'apps/app1/infos/app');

      ref = documentViewGetDocument('apps/app2/infos/app');
      expect(ref.cv(), isA<_AppInfo>());
      expect(ref.path, 'apps/app2/infos/app');

      ref = documentViewGetDocument('apps/app1/infos/dummy');
      expect(ref.cv(), isA<CvFirestoreMapDocument>());
    });
  });
}
