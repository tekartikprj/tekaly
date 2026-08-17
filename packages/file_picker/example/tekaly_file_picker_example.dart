// ignore_for_file: avoid_print

import 'package:tekaly_file_picker/file_picker.dart';
import 'package:tekaly_file_picker/file_picker_memory.dart';

/// Business code, it only depends on the [TekalyFilePicker] interface so it can
/// run anywhere (flutter app, test, cli) and be easily mocked.
Future<String?> pickAndDescribeImage(TekalyFilePicker filePicker) async {
  var file = await filePicker.pickImageFile();
  if (file == null) {
    /// Cancelled by the user
    return null;
  }
  var bytes = await file.readAsBytes();
  return '${file.name} (${file.extension}): ${bytes.length} byte(s)';
}

/// Reading a big file, chunk by chunk.
Future<int> countBytes(TekalyPickedFile file) async {
  var count = 0;
  await for (var chunk in file.readAsByteStream()) {
    count += chunk.length;
  }
  return count;
}

Future<void> main() async {
  /// In a flutter app: `initTekalyFilePickerFlutter()` (from
  /// `package:tekaly_file_picker_flutter/file_picker_flutter.dart`), which sets
  /// the global `tekalyFilePicker`.
  ///
  /// Here (and in tests), an in memory implementation: the files below are the
  /// ones the simulated user can pick.
  var filePicker = TekalyFilePickerMemory();
  filePicker.addFile(name: 'logo.png', bytes: [137, 80, 78, 71]);
  filePicker.addTextFile(name: 'notes.txt', text: 'Hello world');
  filePicker.addFile(name: 'clip.mp4', bytes: List.generate(1024, (i) => i));

  /// Only the image matches
  print(await pickAndDescribeImage(filePicker));

  /// Any file, the first one here
  var file = await filePicker.pickAnyFile();
  print('any: ${file?.name}');

  /// Filtering by extension
  var textFile = await filePicker.pickCustomFile(allowedExtensions: ['txt']);
  print('text: ${await textFile?.readAsString()}');

  /// Multiple files, images and videos
  var mediaFiles = await filePicker.pickFiles(type: TekalyPickFileType.media);
  print('media: ${mediaFiles.map((file) => file.name).toList()}');

  /// Reading chunk by chunk
  print('clip.mp4: ${await countBytes(mediaFiles.last)} byte(s)');

  /// Simulating a user cancelling the dialog
  filePicker.cancelled = true;
  print('cancelled: ${await pickAndDescribeImage(filePicker)}');
  filePicker.cancelled = false;

  /// What the code above asked for
  print('requests:');
  for (var request in filePicker.requests) {
    print('  $request');
  }

  /// The global picker, for apps that don't want to pass it around
  tekalyFilePicker = filePicker;
  print('global: ${(await tekalyFilePicker.pickAnyFile())?.name}');
}
