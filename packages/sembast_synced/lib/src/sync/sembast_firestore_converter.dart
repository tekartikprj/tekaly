/// Compat: the converter now lives in `tekaly_synced_db_common`.
library;

export 'package:tekaly_synced_db_common/synced_db_common_firestore.dart'
    show
        isBasicTypeOrNull,
        sembastToFirestore,
        firestoreToSembast,
        mapSembastToFirestore,
        mapFirestoreToSembast,
        MapSembastFromToFirestoreExt,
        cvRecordFromSnapshot,
        metaInfoRecordFromSnapshot,
        sourceRecordFromSnapshot,
        sourceRecordFromSnapshots;
