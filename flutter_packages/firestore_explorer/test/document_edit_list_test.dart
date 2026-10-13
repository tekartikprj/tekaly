import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

class _ListDoc extends CvFirestoreDocumentBase {
  final tags = CvListField<String>('tags');

  @override
  CvFields get fields => [tags];
}

Finder _itemIcon(String text, IconData icon) => find.descendant(
  of: find.widgetWithText(ListTile, text),
  matching: find.byIcon(icon),
);

void main() {
  cvAddConstructors([_ListDoc.new]);
  testWidgets('list items of basic values', (tester) async {
    var firestore = newFirestoreMemory();
    var docRef = CvCollectionReference<_ListDoc>('root').doc('1');
    await tester.runAsync(
      () => docRef.set(firestore, _ListDoc()..tags.v = ['a', 'b', 'c']),
    );
    var controller = FsDocumentEditController<_ListDoc>(
      firestore: firestore,
      docRef: docRef,
    );
    await tester.runAsync(() => controller.futureEditedDocument);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FsDocumentEdit(controller: controller),
          ),
        ),
      ),
    );
    // Let the edited document future complete
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    // Each item is shown once
    expect(find.widgetWithText(ListTile, 'a'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'b'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'c'), findsOneWidget);

    // An edit reaches the document
    await tester.tap(_itemIcon('b', Icons.edit));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.pump();
    expect(controller.editedDocument.tags.v, ['a', 'edited', 'c']);

    // A delete removes the item from the list
    await tester.tap(_itemIcon('a', Icons.delete));
    await tester.pump();
    expect(controller.editedDocument.tags.v, ['edited', 'c']);
    expect(find.widgetWithText(ListTile, 'a'), findsNothing);
    // The pending text edit does not move to the next item
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(ListTile, 'edited'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'c'), findsOneWidget);

    controller.close();
  });
}
