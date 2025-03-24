import 'package:sembast/sembast.dart' as sembast;
import 'package:tekaly_sembast_synced/src/api/import_common.dart';
import 'package:tekaly_sembast_synced/src/sembast/sembast_import.dart';
import 'package:tekaly_sembast_synced/src/sync/synced_db_lib.dart';
import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';

/// Sembast synced source
abstract class SyncedSourceSembast implements SyncedSource {
  /// The sembast database
  sembast.Database get database;
  factory SyncedSourceSembast({required sembast.Database database}) =>
      _SyncedSourceSembast(database: database);
}

String _generateSyncId(String store, String key) {
  return '$store|$key';
}

String _sourceSyncId({String? syncId, String? store, String? key}) {
  assert((syncId != null) || (store != null && key != null));
  return (store == null || key == null) ? syncId! : _generateSyncId(store, key);
}

/// Helper
extension on SyncedDataSourceRef {
  /// New source sync id
  String get sourceSyncId =>
      _sourceSyncId(syncId: syncId, store: store, key: key);
}

/// Helper
extension on CvSyncedSourceRecord {
  /// New source sync id
  String get sourceSyncId {
    var record = this.record.v;
    return _sourceSyncId(
      syncId: syncId.v,
      store: record?.store.v,
      key: record?.key.v,
    );
  }

  void _fixSyncId() {
    syncId.setValue(sourceSyncId);
  }
}

/// Sembast record
class DbMetaInfoRecord extends DbStringRecordBase with CvMetaInfoRecordMixin {}

class DbDataSourceRecord extends DbStringRecordBase
    with SyncedSourceRecordMixin {}

class _SyncedSourceSembast
    with SyncedSourceDefaultMixin
    implements SyncedSourceSembast {
  @override
  final sembast.Database database;

  /// Enforced synchronizer version, if any
  int? _version;

  /// Enforced synchronizer version, if any or version read
  int? get version => _version;

  static const dataCollectionId = 'data';
  static const metaCollectionId = 'meta';
  static const metaInfoDocumentId = 'info';

  final dataCollection = cvStringStoreFactory.store<DbDataSourceRecord>(
    dataCollectionId,
  );
  final metaCollection = cvStringStoreFactory.store(metaCollectionId);
  late final metaInfoReference = metaCollection
      .castV<DbMetaInfoRecord>()
      .record(metaInfoDocumentId);

  @override
  Future<void> close() async {
    await database.close();
  }

  _SyncedSourceSembast({required this.database}) {
    initBuilders();
    cvAddConstructors([DbMetaInfoRecord.new, DbDataSourceRecord.new]);
  }

  DbDataSourceRecord _toDb(CvSyncedSourceRecord record) {
    if (record is! DbDataSourceRecord) {
      var sourceSyncId = record.sourceSyncId;

      /// Copy fields
      record =
          dataCollection.record(sourceSyncId).cv()
            // No longer set in the record
            //..syncId.setValue(record.syncId.v)
            ..syncChangeId.setValue(record.syncChangeId.v)
            ..record.setValue(record.record.v);
    }

    /// Set timestamp (info only?)
    return record..syncTimestamp.v = DbTimestamp.now();
  }

  /// Must set lastChangeId!
  @override
  @visibleForTesting
  Future<void> putRawRecord(CvSyncedSourceRecord record) async {
    var dbSourceRecord = _toDb(record);
    var dbSourceRecordRef = dataCollection.record(dbSourceRecord.sourceSyncId);
    try {
      await dbSourceRecord.put(database);
    } catch (e) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Error $e while putting record at $dbSourceRecordRef');
      }

      rethrow;
    }
  }

  @override
  Future<CvSyncedSourceRecord?> putSourceRecord(
    CvSyncedSourceRecord record,
  ) async {
    fixAndCheckPutSyncedRecord(record);
    var dbSourceRecord = _toDb(record);

    var sourceSyncId = record.sourceSyncId;
    // Warning this does not work in non authenticated mode
    // and even rest auth (not service account).
    await database.transaction((txn) async {
      var meta = await txnGetMetaInfo(txn);

      // increment change id
      var lastChangeId = (meta.lastChangeId.v ?? 0) + 1;

      // Set record
      dbSourceRecord.syncChangeId.setValue(lastChangeId);
      dbSourceRecord = await dataCollection
          .record(sourceSyncId)
          .put(txn, dbSourceRecord);

      /// Set meta
      meta.lastChangeId.setValue(lastChangeId);
      await metaInfoReference.put(txn, meta);
    });
    dbSourceRecord._fixSyncId();

    return dbSourceRecord;
  }

  @override
  Future<CvMetaInfoRecord?> getMetaInfo() => txnGetMetaInfoOrNull(database);

  Future<DbMetaInfoRecord?> txnGetMetaInfoOrNull(sembast.DatabaseClient txn) =>
      metaInfoReference.get(txn);
  Future<DbMetaInfoRecord> txnGetMetaInfo(sembast.DatabaseClient txn) async =>
      (await txnGetMetaInfoOrNull(txn)) ?? metaInfoReference.cv();

  @override
  Future<CvMetaInfoRecord?> putMetaInfo(CvMetaInfoRecord info) async {
    await database.transaction((txn) async {
      var existing = await txnGetMetaInfo(txn);
      // minIncrementalChangeId can only be later!
      if (existing.minIncrementalChangeId.v != null) {
        if (info.minIncrementalChangeId.v != null) {
          if (info.minIncrementalChangeId.v!.compareTo(
                existing.minIncrementalChangeId.v!,
              ) <
              0) {
            throw StateError(
              'minIncrementTimestamp ${info.minIncrementalChangeId.v} cannot be less then existing ${existing.minIncrementalChangeId.v}',
            );
          }
        }
      }
      if (info.lastChangeId.hasValue) {
        existing.lastChangeId.setValue(info.lastChangeId.v);
      }
      if (info.minIncrementalChangeId.hasValue) {
        existing.minIncrementalChangeId.setValue(info.minIncrementalChangeId.v);
      }
      if (info.version.hasValue) {
        existing.version.setValue(info.version.v);
      }
      await metaInfoReference.put(txn, existing);
    });
    return getMetaInfo();
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(
    SyncedDataSourceRef sourceRef,
  ) async {
    var recordId = sourceRef.sourceSyncId;

    var doc = await _clientGetSourceRecordById(database, recordId);

    if (doc != null) {
      if (doc.recordStore == sourceRef.store &&
          doc.recordKey == sourceRef.key) {
        doc._fixSyncId();
        return doc;
      }

      if (debugSyncedSync) {
        // ignore: avoid_print
        print('getSourceRecord Invalid record $doc for ref $sourceRef');
      }
    } else {
      // Old format compat, unused
    }
    return null;
  }

  Future<CvSyncedSourceRecord?> _clientGetSourceRecordById(
    sembast.DatabaseClient client,
    String syncId,
  ) => dataCollection.record(syncId).get(client);

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) async {
    includeDeleted ??= false;
    var query = dataCollection.query(
      finder: Finder(
        sortOrders: [SortOrder(syncChangeIdKey)],
        limit: limit,
        filter:
            afterChangeId != null
                ? Filter.greaterThan(syncChangeIdKey, afterChangeId)
                : null,
      ),
    );

    List<DbDataSourceRecord> dbSourceRecords;
    try {
      dbSourceRecords = await query.getRecords(database);
    } catch (e) {
      if (debugSyncedSync) {
        // ignore: avoid_print
        print('Error $e while getting record list at $query');
      }
      rethrow;
    }
    /*
    return sourceRecordFromSnapshots(querySnapshot.docs)
        .cast<SyncedSourceRecord>();

     */

    var list =
        dbSourceRecords
            .where(
              (element) =>
                  (includeDeleted ?? false) ? true : !element.isDeleted,
            )
            .map((record) {
              record._fixSyncId();
              return record;
            })
            .toList();
    var lastChangeNum = dbSourceRecords.lastOrNull?.syncChangeId.v;
    return SyncedSourceRecordList(list, lastChangeNum);
  }

  @override
  Stream<CvMetaInfoRecord?> onMetaInfo({Duration? checkDelay}) {
    return metaInfoReference.onRecord(database);
  }
}
