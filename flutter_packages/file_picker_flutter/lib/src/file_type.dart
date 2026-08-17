import 'package:file_picker/file_picker.dart' as fp;
import 'package:tekaly_file_picker/file_picker.dart';

/// The `file_picker` type matching a [TekalyPickFileType].
fp.FileType toFilePickerFileType(TekalyPickFileType type) => switch (type) {
  TekalyPickFileType.any => fp.FileType.any,
  TekalyPickFileType.media => fp.FileType.media,
  TekalyPickFileType.image => fp.FileType.image,
  TekalyPickFileType.video => fp.FileType.video,
  TekalyPickFileType.audio => fp.FileType.audio,
  TekalyPickFileType.custom => fp.FileType.custom,
};
