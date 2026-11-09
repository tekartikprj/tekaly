// Widget tests of the playground, driving the in memory picker.
//
// This is the whole point of `tekaly_file_picker`: the exact same screen code
// runs against a mock, no dialog, no plugin, no platform channel.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tekaly_file_picker_flutter_example/src/playground_screen.dart';

void main() {
  Future<void> pumpPlayground(WidgetTester tester) async {
    /// Big enough for the whole playground to be laid out at once
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PlaygroundScreen()));

    /// Switch to the in memory implementation
    await tester.tap(find.text('Memory'));
    await tester.pumpAndSettle();
  }

  testWidgets('pickFile picks the first in memory file', (tester) async {
    await pumpPlayground(tester);

    await tester.tap(find.text('pickFile'));
    await tester.pumpAndSettle();

    expect(find.text('red.png'), findsOneWidget);
  });

  testWidgets('pickFiles filters by type', (tester) async {
    await pumpPlayground(tester);

    /// Images only
    await tester.tap(find.text('image'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('pickFiles'));
    await tester.pumpAndSettle();

    expect(find.text('red.png'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    expect(find.text('clip.mp4'), findsNothing);
  });

  testWidgets('a new pick does not show what was read of the previous one', (
    tester,
  ) async {
    await pumpPlayground(tester);
    Finder readAsBytesField() =>
        find.textContaining('readAsBytes()', findRichText: true);

    await tester.tap(find.text('pickFile'));
    await tester.pumpAndSettle();
    expect(find.text('red.png'), findsOneWidget);
    await tester.tap(find.text('readAsBytes'));
    await tester.pumpAndSettle();
    expect(readAsBytesField(), findsOneWidget);

    /// json,txt: notes.txt, never read
    await tester.tap(find.text('custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pickFile'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(readAsBytesField(), findsNothing);
  });

  testWidgets('a cancelled dialog picks nothing', (tester) async {
    await pumpPlayground(tester);

    await tester.tap(find.text('Simulate a cancelled dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('pickFiles'));
    await tester.pumpAndSettle();

    expect(find.text('red.png'), findsNothing);
    expect(find.textContaining('Nothing picked yet'), findsOneWidget);
  });
}
