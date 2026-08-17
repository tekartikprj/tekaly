// Widget tests of the playground, driving the in memory file picker.
//
// Not on the web, `downloadFile` saves through the global `tekalyFilePicker`,
// so a `TekalyFilePickerMemory` is all that is needed to test a download: no
// dialog, no plugin, no platform channel.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_file_download_flutter_example/src/download_playground_screen.dart';
import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';

void main() {
  late TekalyFilePickerMemory filePicker;

  setUp(() {
    filePicker = TekalyFilePickerMemory(directoryPath: '/memory/dir');
    tekalyFilePicker = filePicker;
  });

  Future<void> pumpPlayground(WidgetTester tester) async {
    /// Big enough for the whole playground to be laid out at once
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: DownloadPlaygroundScreen()),
    );
  }

  Future<void> selectSample(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ChoiceChip, label));
    await tester.pumpAndSettle();
  }

  testWidgets('downloadFile saves the text sample', (tester) async {
    await pumpPlayground(tester);

    await tester.tap(find.text('downloadFile'));
    await tester.pumpAndSettle();

    var request = filePicker.saveRequests.single;
    expect(request.fileName, 'hello.txt');
    expect(request.mimeType, 'text/plain');
    expect(utf8.decode(request.bytes), contains('Hello World'));
    expect(find.textContaining('hello.txt'), findsWidgets);
  });

  testWidgets('the mime type comes from the extension', (tester) async {
    await pumpPlayground(tester);

    await selectSample(tester, 'Json');
    expect(find.text('DownloadFileInfo.mimeType: application/json'), findsOne);

    /// `.md` is not known, the default is used
    await selectSample(tester, 'Markdown');
    expect(
      find.text('DownloadFileInfo.mimeType: application/octet-stream'),
      findsOne,
    );

    /// unless the sample provides one
    await selectSample(tester, 'Csv');
    expect(find.text('DownloadFileInfo.mimeType: text/csv'), findsOne);

    await tester.tap(find.text('downloadFile'));
    await tester.pumpAndSettle();

    expect(filePicker.saveRequests.single.mimeType, 'text/csv');
  });

  testWidgets('the lazy content is generated after the delay', (tester) async {
    await pumpPlayground(tester);

    await tester.tap(find.text('downloadFile after 1s'));
    await tester.pump();

    /// Still generating, nothing saved yet
    expect(filePicker.saveRequests, isEmpty);

    await tester.pump(lazyDelay);
    await tester.pumpAndSettle();

    expect(filePicker.saveRequests.single.fileName, 'hello.txt');
    expect(find.textContaining('downloadFile (lazy)'), findsOne);
  });

  testWidgets('downloadImage saves a png', (tester) async {
    await pumpPlayground(tester);

    await selectSample(tester, 'Png');
    await tester.tap(find.text('downloadImage'));
    await tester.pumpAndSettle();

    var request = filePicker.saveRequests.single;
    expect(request.fileName, 'checker.png');
    expect(request.mimeType, 'image/png');
    expect(request.bytes.length, greaterThan(16));
  });

  testWidgets('a cancelled save dialog is not an error', (tester) async {
    await pumpPlayground(tester);
    filePicker.cancelled = true;

    await tester.tap(find.text('downloadFile'));
    await tester.pumpAndSettle();

    expect(filePicker.saveRequests.single.fileName, 'hello.txt');
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('the sized samples use the size field', (tester) async {
    await pumpPlayground(tester);

    await selectSample(tester, 'Binary');
    await tester.enterText(find.widgetWithText(TextField, 'size (kB)'), '2');
    await tester.pumpAndSettle();

    await tester.tap(find.text('downloadFile'));
    await tester.pumpAndSettle();

    var request = filePicker.saveRequests.single;
    expect(request.fileName, 'data.bin');
    expect(request.bytes.length, 2 * 1024);
    expect(request.mimeType, 'application/octet-stream');
  });
}
