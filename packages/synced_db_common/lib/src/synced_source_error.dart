import 'package:tekartik_firebase_firestore/firestore.dart';

/// An error of a synced source that retrying will not fix (no access,
/// invalid data...), unlike a network error.
///
/// Thrown by custom sources (and tests) to report a permanent error, see
/// [isSyncedSourcePermanentError].
class SyncedSourcePermanentException implements Exception {
  /// Error message.
  final String message;

  /// Error code (a firestore one like `permission-denied`), if any.
  final String? code;

  /// Permanent error.
  SyncedSourcePermanentException(this.message, {this.code});

  @override
  String toString() =>
      'SyncedSourcePermanentException(${code == null ? '' : '$code: '}$message)';
}

/// Firestore error codes that retrying will not fix.
const syncedSourcePermanentErrorCodes = {
  'permission-denied',
  'unauthenticated',
  'invalid-argument',
  'failed-precondition',
  'unimplemented',
};

final _cloudFirestoreCodeRegExp = RegExp(r'\[cloud_firestore/([a-z-]+)\]');

/// The firestore error code of [error], if any: a [FirestoreException] code
/// (rest, sim...) or the code of a flutter `FirebaseException`
/// (`[cloud_firestore/permission-denied] ...`).
String? syncedSourceErrorCode(Object error) {
  if (error is SyncedSourcePermanentException) {
    return error.code;
  }
  if (error is FirestoreException) {
    return error.code;
  }
  return _cloudFirestoreCodeRegExp.firstMatch(error.toString())?.group(1);
}

/// True when retrying will not fix [error]: a [SyncedSourcePermanentException]
/// or a firestore error with one of [syncedSourcePermanentErrorCodes]
/// (`permission-denied`...). Any other error (network, offline, unavailable,
/// unknown) is transient.
bool isSyncedSourcePermanentError(Object error) {
  if (error is SyncedSourcePermanentException) {
    return true;
  }
  var code = syncedSourceErrorCode(error);
  return code != null && syncedSourcePermanentErrorCodes.contains(code);
}
