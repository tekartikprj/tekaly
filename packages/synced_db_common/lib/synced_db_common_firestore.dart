/// Firestore synced source, on top of `synced_db_common.dart`.
library;

export 'src/auto_synced_firestore.dart'
    show
        AutoSynchronizedFirestoreOptionsCommon,
        AutoSynchronizedFirestoreSyncedDbCommon,
        AutoSynchronizedFirestoreSyncedDbBase;
export 'src/synced_source_firestore.dart'
    show SyncedSourceFirestore, SyncedSourceOfflineException;
export 'src/synced_source_firestore_converter.dart';
export 'synced_db_common.dart';
