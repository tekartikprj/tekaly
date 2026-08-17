/// Platform agnostic file picker interface (no flutter, no io, no web).
library;

export 'src/file_picker.dart'
    show
        TekalyFilePicker,
        TekalyFilePickerExtension,
        TekalyPickFileType,
        checkTekalyPickFileArguments,
        tekalyDefaultMimeType,
        tekalyFilePicker,
        tekalyFilePickerOrNull;
export 'src/file_type.dart'
    show
        tekalyAudioFileExtensions,
        tekalyImageFileExtensions,
        tekalyPickFileTypeExtensions,
        tekalyVideoFileExtensions;
export 'src/picked_file.dart' show TekalyPickedFile, TekalyPickedFileExtension;
