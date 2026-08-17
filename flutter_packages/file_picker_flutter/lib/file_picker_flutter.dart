/// Flutter file picker, on top of `file_picker`.
library;

/// The whole interface, so that an app only needs this import.
export 'package:tekaly_file_picker/file_picker.dart';

export 'src/file_picker_flutter.dart'
    show
        TekalyFilePickerFlutter,
        initTekalyFilePickerFlutter,
        tekalyFilePickerFlutter;
export 'src/file_type.dart' show toFilePickerFileType;
export 'src/picked_file_platform_file.dart'
    show TekalyPickedFilePlatformFile, TekalyPickedFileXFile;
