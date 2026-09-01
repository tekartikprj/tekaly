/// Sync a firestore collection offline with a minimal number of reads.
///
/// Client and common side: the tracked collection helper, the change log
/// model and the read only source a consumer synchronizes from.
///
/// See `synced_firestore_trigger.dart` for the server side (cloud function
/// trigger, change log rebuild) and `synced_firestore_sdb.dart` for the local
/// sdb mirror.
library;

export 'src/synced_fs_change.dart'
    show
        CvSyncedFsChangeRecord,
        CvSyncedFsChangeRecordExt,
        SyncedFsChangeList,
        SyncedFsChangeOrigin,
        changeChangeIdFieldKey,
        changeDataFieldKey,
        changeDeletedFieldKey,
        changeDocIdFieldKey,
        changeOriginFieldKey,
        changeTimestampFieldKey,
        changeUpdateTimeFieldKey,
        syncedFsChangeDocId,
        syncedFsChangeDocIdToChangeId;
export 'src/synced_fs_collection.dart'
    show SyncedFsCollection, SyncedFsCollectionOptions;
export 'src/synced_fs_document.dart'
    show
        CvSyncedFsDocumentMapExt,
        CvSyncedFsDocumentSyncedInfo,
        syncedChangeIdFieldKey,
        syncedChangeIdFieldPath,
        syncedDeletedFieldKey,
        syncedDeletedFieldPath,
        syncedFieldKey,
        syncedTimestampFieldKey,
        syncedTimestampFieldPath;
export 'src/synced_fs_meta.dart'
    show
        SyncedFsMetaInfoRecord,
        metaChangeLogChangeIdKey,
        metaLastChangeIdKey,
        metaLastReconcileTimestampKey,
        metaMinIncrementalChangeIdKey,
        metaVersionIdKey;
export 'src/synced_fs_refs.dart'
    show
        SyncedFsCollectionRefs,
        cvInitSyncedFsBuilders,
        syncedFsChangesCollectionSuffix,
        syncedFsMetaCollectionSuffix,
        syncedFsMetaInfoDocumentId;
export 'src/synced_fs_source.dart'
    show
        SyncedFsFirestoreSource,
        SyncedFsSnapshot,
        SyncedFsSource,
        SyncedFsSourceExt,
        syncedFsDefaultStepLimit;
