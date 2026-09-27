import 'package:tekaly_synced_db_common/synced_db_common_firestore.dart';
import 'package:tekartik_firebase_firestore/firestore.dart';
import 'package:test/test.dart';

class _FirestoreException extends FirestoreException {
  _FirestoreException(super.code, super.message);
}

/// The text of a flutter (cloud_firestore) FirebaseException.
class _FlutterFirebaseException implements Exception {
  final String code;

  _FlutterFirebaseException(this.code);

  @override
  String toString() => '[cloud_firestore/$code] Some message';
}

void main() {
  group('synced_source_error', () {
    test('permanent errors', () {
      for (var error in <Object>[
        SyncedSourcePermanentException('no access'),
        _FirestoreException('permission-denied', 'no access'),
        _FirestoreException('unauthenticated', 'no user'),
        _FirestoreException('failed-precondition', 'missing index'),
        _FlutterFirebaseException('permission-denied'),
      ]) {
        expect(isSyncedSourcePermanentError(error), isTrue, reason: '$error');
      }
    });
    test('transient errors', () {
      for (var error in <Object>[
        SyncedSourceOfflineException('cache'),
        SyncedSourceFailureException(),
        _FirestoreException('unavailable', 'offline'),
        _FirestoreException('deadline-exceeded', 'slow'),
        _FlutterFirebaseException('unavailable'),
        StateError('other'),
      ]) {
        expect(isSyncedSourcePermanentError(error), isFalse, reason: '$error');
      }
    });
    test('code', () {
      expect(
        syncedSourceErrorCode(_FirestoreException('not-found', 'missing')),
        'not-found',
      );
      expect(
        syncedSourceErrorCode(_FlutterFirebaseException('unavailable')),
        'unavailable',
      );
      expect(
        syncedSourceErrorCode(
          SyncedSourcePermanentException('no', code: 'permission-denied'),
        ),
        'permission-denied',
      );
      expect(syncedSourceErrorCode(StateError('other')), isNull);
    });
  });
  group('synced_db_sync_status', () {
    test('satisfies', () {
      SyncedDbSyncStatus status(SyncedDbInitialSync initialSync) =>
          SyncedDbSyncStatus(
            initialSync: initialSync,
            activity: SyncedDbSyncActivity.idle,
          );
      var never = status(SyncedDbInitialSync.never);
      var previous = status(SyncedDbInitialSync.previousSession);
      var current = status(SyncedDbInitialSync.thisSession);
      expect(never.satisfies(SyncedDbInitialSyncPolicy.none), isTrue);
      expect(never.satisfies(SyncedDbInitialSyncPolicy.any), isFalse);
      expect(previous.satisfies(SyncedDbInitialSyncPolicy.any), isTrue);
      expect(
        previous.satisfies(SyncedDbInitialSyncPolicy.thisSession),
        isFalse,
      );
      expect(current.satisfies(SyncedDbInitialSyncPolicy.thisSession), isTrue);
      expect(current, status(SyncedDbInitialSync.thisSession));
      expect(current, isNot(previous));
    });
    test('permanentErrorDelay', () {
      expect(
        const SyncedDbSynchronizerRetryOptions().permanentErrorDelay,
        const Duration(minutes: 1),
      );
      expect(
        const SyncedDbSynchronizerRetryOptions.noRetry().permanentErrorDelay,
        Duration.zero,
      );
    });
  });
}
