import 'package:flutter/material.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

import 'src/download_playground_screen.dart';

void main() {
  /// Once at startup. `downloadFile` uses the global [tekalyFilePicker] to save
  /// the file when not on the web, and falls back to the flutter implementation
  /// when it has not been initialized.
  initTekalyFilePickerFlutter();

  runApp(const FileDownloadPlaygroundApp());
}

/// tekaly_file_download playground.
class FileDownloadPlaygroundApp extends StatelessWidget {
  /// tekaly_file_download playground.
  const FileDownloadPlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'tekaly_file_download playground',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
    ),
    home: const DownloadPlaygroundScreen(),
  );
}
