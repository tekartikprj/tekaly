/// Flutter file download helper.
///
/// On the web the browser downloads the file, elsewhere a save dialog is shown.
library;

export 'package:tekaly_file_download_web/file_download.dart'
    show
        // Web only, a no op elsewhere: feeds an existing anchor, so that the
        // browser cannot block a download triggered too late
        anchorSelectorSetDownloadFileInfo,
        DownloadFileInfo;
export 'package:tekaly_file_download_web/mime_type.dart' show filenameMimeType;

export 'src/download/download_file.dart' show downloadFile;
