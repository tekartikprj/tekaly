import 'package:tekaly_firestore_synced/src/synced_fs_change.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_document.dart';
import 'package:tekaly_firestore_synced/src/synced_fs_meta.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';

var _buildersInitialized = false;

/// Initialize the cv builders needed by the synced firestore helpers.
void cvInitSyncedFsBuilders() {
  if (!_buildersInitialized) {
    _buildersInitialized = true;
    cvAddConstructors([
      SyncedFsMetaInfoRecord.new,
      CvSyncedFsDocumentSyncedInfo.new,
      CvSyncedFsChangeRecord.new,
    ]);
  }
}

/// Suffix of the meta collection, holding a single `info` document.
const syncedFsMetaCollectionSuffix = '_meta';

/// Suffix of the immutable change log collection.
const syncedFsChangesCollectionSuffix = '_changes';

/// The `info` document id in the meta collection.
const syncedFsMetaInfoDocumentId = 'info';

/// The 3 references involved in a synced collection:
/// - the tracked collection itself (`<path>`)
/// - the immutable change log (`<path>_changes`)
/// - the meta information (`<path>_meta/info`)
///
/// Shared by the writer ([SyncedFsCollection]), the trigger, the change log
/// rebuilder and the read only source.
class SyncedFsCollectionRefs {
  /// The tracked collection path.
  final String path;

  /// The tracked collection, untyped.
  late final CvCollectionReference<CvFirestoreMapDocument> collection =
      CvCollectionReference<CvFirestoreMapDocument>(path);

  /// The immutable change log collection.
  late final CvCollectionReference<CvSyncedFsChangeRecord> changesCollection =
      CvCollectionReference<CvSyncedFsChangeRecord>(
        '$path$syncedFsChangesCollectionSuffix',
      );

  /// The meta collection.
  late final CvCollectionReference<SyncedFsMetaInfoRecord> metaCollection =
      CvCollectionReference<SyncedFsMetaInfoRecord>(
        '$path$syncedFsMetaCollectionSuffix',
      );

  /// The meta info document (`<path>_meta/info`).
  late final CvDocumentReference<SyncedFsMetaInfoRecord> metaInfoDocRef =
      metaCollection.doc(syncedFsMetaInfoDocumentId);

  /// Refs for the collection at [path].
  SyncedFsCollectionRefs({required this.path}) {
    cvInitSyncedFsBuilders();
  }

  /// Refs for an already typed collection reference.
  SyncedFsCollectionRefs.fromCollection(CvCollectionReference collection)
    : this(path: collection.path);

  /// A change log entry reference for [changeId].
  CvDocumentReference<CvSyncedFsChangeRecord> changeDocRef(int changeId) =>
      changesCollection.doc(syncedFsChangeDocId(changeId));

  @override
  String toString() => 'SyncedFsCollectionRefs($path)';
}
