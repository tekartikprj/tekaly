import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekaly_firestore_explorer/src/document_clipboard_controller.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

class _NameDoc extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');

  @override
  CvFields get fields => [name];
}

void main() {
  cvAddConstructors([_NameDoc.new]);
  testWidgets('cancelled delete', (tester) async {
    var firestore = newFirestoreMemory();
    var docRef = CvCollectionReference<_NameDoc>('root').doc('1');
    await tester.runAsync(
      () => docRef.set(firestore, _NameDoc()..name.v = 'n'),
    );
    expect(gDocumentClipboardController.doc, isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: FsDocumentViewScreen(doc: docRef, firestore: firestore),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await settle();
    await tester.tap(find.byIcon(Icons.delete));
    await settle();
    await tester.tap(find.text('No'));
    await settle();

    // Neither deleted nor copied to the clipboard
    expect(gDocumentClipboardController.doc, isNull);
    expect((await tester.runAsync(() => docRef.get(firestore)))?.name.v, 'n');
    await tester.pumpWidget(const SizedBox());
  });
}
