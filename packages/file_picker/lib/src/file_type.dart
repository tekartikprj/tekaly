import 'file_picker.dart';

/// Lower case extensions (without the leading dot) considered as images.
const tekalyImageFileExtensions = <String>{
  'bmp',
  'gif',
  'heic',
  'heif',
  'jpeg',
  'jpg',
  'png',
  'svg',
  'tif',
  'tiff',
  'webp',
};

/// Lower case extensions (without the leading dot) considered as videos.
const tekalyVideoFileExtensions = <String>{
  '3gp',
  'avi',
  'flv',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'webm',
  'wmv',
};

/// Lower case extensions (without the leading dot) considered as audio.
const tekalyAudioFileExtensions = <String>{
  'aac',
  'flac',
  'm4a',
  'mp3',
  'ogg',
  'opus',
  'wav',
  'wma',
};

/// The lower case extensions matching [type], `null` when everything matches
/// ([TekalyPickFileType.any]).
///
/// [allowedExtensions] is only used for [TekalyPickFileType.custom].
Set<String>? tekalyPickFileTypeExtensions(
  TekalyPickFileType type, [
  List<String>? allowedExtensions,
]) => switch (type) {
  TekalyPickFileType.any => null,
  TekalyPickFileType.image => tekalyImageFileExtensions,
  TekalyPickFileType.video => tekalyVideoFileExtensions,
  TekalyPickFileType.audio => tekalyAudioFileExtensions,
  TekalyPickFileType.media => {
    ...tekalyImageFileExtensions,
    ...tekalyVideoFileExtensions,
  },
  TekalyPickFileType.custom =>
    (allowedExtensions ?? const <String>[])
        .map((extension) => extension.toLowerCase())
        .toSet(),
};
