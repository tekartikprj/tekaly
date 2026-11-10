import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

class _CopyDoc extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');
  final tags = CvListField<String>('tags');

  @override
  CvFields get fields => [name, tags];
}

void main() {
  cvAddConstructors([_CopyDoc.new]);
  testWidgets('a tap copies the value shown', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var firestore = newFirestoreMemory();
    var docRef = CvCollectionReference<_CopyDoc>('root').doc('1');
    await tester.runAsync(
      () => docRef.set(
        firestore,
        _CopyDoc()
          ..name.v = 'my name'
          ..tags.v = ['tag_a', 'tag_b'],
      ),
    );
    var controller = FsDocumentViewController<_CopyDoc>(
      firestore: firestore,
      docRef: docRef,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FsDocumentView(controller: controller),
          ),
        ),
      ),
    );
    // Let the document stream emit
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    // A field: its value
    await tester.tap(find.widgetWithText(ListTile, 'my name'));
    await tester.pump(const Duration(seconds: 5));
    expect(copied, 'my name');

    // A list item of a basic value: its value too
    await tester.tap(find.widgetWithText(ListTile, 'tag_b'));
    await tester.pump(const Duration(seconds: 5));
    expect(copied, 'tag_b');

    controller.close();
    await tester.pumpWidget(Container());
  });
}
