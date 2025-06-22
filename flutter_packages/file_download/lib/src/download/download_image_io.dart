import 'package:file_picker/file_picker.dart';

import 'download_image.dart';

Future<void> downloadImage(DownloadImageInfo imageInfo) async {
  await FilePicker.platform.saveFile(
    bytes: imageInfo.data,
    fileName: imageInfo.filename,
  );
}
