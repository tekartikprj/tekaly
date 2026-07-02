import 'package:sembast/blob.dart';
import 'package:sembast/timestamp.dart';

export 'package:sembast/sembast.dart';
// ignore: implementation_imports_for_file
export 'package:sembast/src/api/protected/codec.dart';

/// Force sembast db type
typedef DbTimestamp = Timestamp;

/// Force sembast db type
typedef DbBlob = Blob;
