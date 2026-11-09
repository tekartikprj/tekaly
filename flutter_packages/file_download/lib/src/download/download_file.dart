import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:tekaly_file_download_web/file_download.dart' as fdw;
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

/// The file picker used to save a file when not on the web.
///
/// The global `tekalyFilePicker` when it has been initialized (a
/// `TekalyFilePickerMemory` in tests in particular), the default flutter
/// implementation otherwise.
TekalyFilePicker get _filePicker =>
    tekalyFilePickerOrNull ?? tekalyFilePickerFlutter;

/// Download a file.
///
/// On the web the browser downloads it (`tekaly_file_download_web`), elsewhere
/// the user is asked where to save it (`tekaly_file_picker_flutter`).
///
/// Completes once done or cancelled: a cancelled dialog is not an error, and
/// nothing tells where the file went (use `tekalyFilePicker.saveFile()` for
/// the saved uri). On the web the global `tekalyFilePicker` is not used, so a
/// `TekalyFilePickerMemory` only records the downloads of a VM test.
Future<void> downloadFile(fdw.DownloadFileInfo fileInfo) async {
  if (kIsWeb) {
    await fdw.downloadFile(fileInfo);
  } else {
    await _filePicker.saveFile(
      fileName: fileInfo.filename,
      bytes: fileInfo.data,
      mimeType: fileInfo.mimeType,
    );
  }
}
