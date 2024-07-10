import 'package:path/path.dart';

var syncedDbExportFilename = 'export.jsonl';
var syncedDbExportMetaFilename = 'export_meta.json';

var assetsRootDataParts = ['assets', 'data'];

/// Default for flutter app
var assetsRootDataPath = url.joinAll(assetsRootDataParts);

var assetsRootDataIoPath = joinAll(assetsRootDataParts);
