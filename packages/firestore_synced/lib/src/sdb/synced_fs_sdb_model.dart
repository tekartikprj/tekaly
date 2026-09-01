import 'package:tekartik_app_cv_sdb/app_cv_sdb.dart';

/// Local sync meta store name, one record per mirrored store.
const syncedFsSdbMetaStoreName = 'local_fs_sync_meta';

/// Local dead letter queue store name.
const syncedFsSdbDeadLetterStoreName = 'local_fs_sync_dlq';

/// Local sync meta store, keyed by the mirrored store name.
final syncedFsSdbMetaStoreRef = scvStringStoreFactory.store<SdbFsSyncMetaInfo>(
  syncedFsSdbMetaStoreName,
);

/// Local dead letter queue store.
final syncedFsSdbDeadLetterStoreRef = scvIntStoreFactory
    .store<SdbFsSyncDeadLetter>(syncedFsSdbDeadLetterStoreName);

/// Dead letters of one store.
final syncedFsSdbDeadLetterByStoreIndexRef = syncedFsSdbDeadLetterStoreRef
    .index<String>('store');

/// Model, for field names.
final syncedFsSdbDeadLetterModel = SdbFsSyncDeadLetter();

/// Where a local mirror stands, one record per mirrored store.
class SdbFsSyncMetaInfo extends ScvStringRecordBase {
  /// The source id, the firestore collection path.
  final source = CvField<String>('source');

  /// The source version, bumped to force a full resynchronization.
  final sourceVersion = CvField<int>('sourceVersion');

  /// Last modification number applied locally, 0 after an empty first sync.
  final lastChangeId = CvField<int>('lastChangeId');

  /// When the last synchronization ran.
  final lastTimestamp = CvField<SdbTimestamp>('lastTimestamp');

  @override
  List<CvField> get fields => [
    source,
    sourceVersion,
    lastChangeId,
    lastTimestamp,
  ];
}

/// A change that could not be applied locally.
///
/// Kept out of the way so that one bad document (an unsupported value type, a
/// content the local schema rejects) does not block the whole synchronization,
/// and can be retried or inspected later.
class SdbFsSyncDeadLetter extends ScvIntRecordBase {
  /// The mirrored store name.
  final store = CvField<String>('store');

  /// The modification number of the change.
  final changeId = CvField<int>('changeId');

  /// The source document id.
  final docId = CvField<String>('docId');

  /// True when the change was a deletion.
  final deleted = CvField<bool>('deleted');

  /// The error message.
  final error = CvField<String>('error');

  /// When it was queued.
  final timestamp = CvField<SdbTimestamp>('timestamp');

  /// How many times applying it failed.
  final retryCount = CvField<int>('retryCount');

  @override
  List<CvField> get fields => [
    store,
    changeId,
    docId,
    deleted,
    error,
    timestamp,
    retryCount,
  ];
}

/// Stores needed by a local mirror, to add to the database schema next to the
/// mirrored store(s):
///
/// ```dart
/// var schema = SdbDatabaseSchema(
///   stores: [itemStoreRef.schema(), ...syncedFsSdbSchema.stores],
/// );
/// ```
final syncedFsSdbSchema = SdbDatabaseSchema(
  stores: [
    syncedFsSdbMetaStoreRef.schema(),
    syncedFsSdbDeadLetterStoreRef.schema(
      autoIncrement: true,
      indexes: [
        syncedFsSdbDeadLetterByStoreIndexRef.schema(
          keyPath: syncedFsSdbDeadLetterModel.store.name,
        ),
      ],
    ),
  ],
);
