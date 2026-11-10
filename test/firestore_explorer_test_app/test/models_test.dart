import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekaly_firestore_explorer_test_app/models.dart';

void main() {
  test('every model of an app info can be read', () {
    initFsBuilders();
    var info = {
      'name': 'info',
      'sub1': {'sub1': 'a'},
      'sub2s': [
        {'sub2': 'b'},
      ],
      'noNameSub1': {'sub1': 'c'},
      'noNameSub2s': [
        {'sub2': 'd'},
      ],
    }.cv<FsAppInfo>();
    expect(info.noNameSub1.v!.sub1.v, 'c');
    expect(info.noNameSub2s.v!.single.sub2.v, 'd');
  });
}
