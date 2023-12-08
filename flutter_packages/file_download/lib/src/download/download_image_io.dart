import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'download_image.dart';

Future<void> downloadImage(DownloadImageInfo imageInfo) async {
  var outputFile = await FilePicker.platform.saveFile(
    //dialogTitle: 'Please select an output file:',
    fileName: imageInfo.filename,
  );

  if (outputFile != null) {
    await File(outputFile).writeAsBytes(imageInfo.data);
    // User canceled the picker
  }
}
