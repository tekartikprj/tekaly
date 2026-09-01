/// Local sdb mirror of a synced firestore collection.
library;

export 'src/sdb/synced_fs_sdb.dart'
    show
        SyncedFsSdbSyncResult,
        SyncedFsSdbSynchronizer,
        cvInitSyncedFsSdbBuilders;
export 'src/sdb/synced_fs_sdb_converter.dart'
    show firestoreMapToSdb, isSdbSupportedTypeOrNull;
export 'src/sdb/synced_fs_sdb_model.dart'
    show
        SdbFsSyncDeadLetter,
        SdbFsSyncMetaInfo,
        syncedFsSdbDeadLetterByStoreIndexRef,
        syncedFsSdbDeadLetterStoreName,
        syncedFsSdbDeadLetterStoreRef,
        syncedFsSdbMetaStoreName,
        syncedFsSdbMetaStoreRef,
        syncedFsSdbSchema;
export 'synced_firestore.dart';
