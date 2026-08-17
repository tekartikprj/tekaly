import 'package:flutter/material.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

import 'src/playground_screen.dart';

void main() {
  /// Once at startup, sets the global [tekalyFilePicker] to the flutter
  /// implementation (`file_picker`, or `file_selector` on linux).
  initTekalyFilePickerFlutter();

  runApp(const FilePickerPlaygroundApp());
}

/// tekaly_file_picker playground.
class FilePickerPlaygroundApp extends StatelessWidget {
  /// tekaly_file_picker playground.
  const FilePickerPlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'tekaly_file_picker playground',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
    ),
    home: const PlaygroundScreen(),
  );
}
