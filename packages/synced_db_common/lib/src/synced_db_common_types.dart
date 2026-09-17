import 'package:sembast/blob.dart';
import 'package:sembast/timestamp.dart';

/// Synced db timestamp (sembast `Timestamp`, also the sdb timestamp type).
typedef SyncedDbTimestamp = Timestamp;

/// Synced db blob (sembast `Blob`, also the sdb blob type).
typedef SyncedDbBlob = Blob;

/// Synced db common transaction
abstract class SyncedDbCommonTransaction implements SyncedDbCommonClient {}

/// Synced db common client
abstract class SyncedDbCommonClient {}

/// Common synced db (sembast or sdb based).
abstract class SyncedDbCommon {}
