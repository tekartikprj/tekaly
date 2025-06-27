import 'package:cv/cv.dart';
import 'package:meta/meta.dart';
import 'package:sembast/timestamp.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tekaly_sembast_synced/synced_db_internals.dart';

typedef _Key = (String store, String key);

class SyncedSourceMemory with SyncedSourceDefaultMixin implements SyncedSource {
  final _lock = Lock();
  var _lastSyncId = 0;
  CvMetaInfo? _metaInfo;
  final _sourceRecordsBySyncId = <String, CvSyncedSourceRecord>{};
  final _sourceRecordsByStoreAndKey = <_Key, CvSyncedSourceRecord>{};

  SyncedSourceMemory() {
    initBuilders();
  }
  @override
  Future<void> close() async {}

  Iterable<CvSyncedSourceRecord> get sorterSourceRecords =>
      _sourceRecordsBySyncId.values.toList()
        ..sort((r1, r2) => r1.syncChangeId.v!.compareTo(r2.syncChangeId.v!));
  @override
  Future<CvMetaInfo?> getMetaInfo() {
    return _lock.synchronized(() {
      return _metaInfo;
    });
  }

  CvMetaInfo? _lockedGetMetaInfo() {
    return _metaInfo;
  }

  CvMetaInfo _lockedPutMetaInfo(CvMetaInfo metaInfo) {
    _metaInfo = metaInfo;
    return _metaInfo!;
  }

  @override
  Future<CvMetaInfo> putMetaInfo(CvMetaInfo info) {
    return _lock.synchronized(() {
      var existing = _lockedGetMetaInfo();
      // timestamp can only be later
      if (existing?.minIncrementalChangeId.v != null) {
        if (info.minIncrementalChangeId.v != null) {
          if (info.minIncrementalChangeId.v!.compareTo(
                existing!.minIncrementalChangeId.v!,
              ) <
              0) {
            throw StateError(
              'minIncrementalChangeId ${info.minIncrementalChangeId.v} cannot be less then existing ${existing.minIncrementalChangeId.v}',
            );
          }
        }
      }
      return _lockedPutMetaInfo(info);
    });
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef) {
    return _lock.synchronized(() async {
      return _lockedGetSourceRecord(sourceRef);
    });
  }

  CvSyncedSourceRecord? _lockedGetSourceRecord(SyncedDataSourceRef sourceRef) {
    if (sourceRef.syncId != null) {
      var record = _sourceRecordsBySyncId[sourceRef.syncId!];
      if (record != null) {
        if (record.recordStore == sourceRef.store &&
            record.recordKey == sourceRef.key) {
          return record;
        }
      }
    }
    return _sourceRecordsByStoreAndKey[(sourceRef.store!, sourceRef.key!)];
  }

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record) {
    return _lock.synchronized(() {
      fixAndCheckPutSyncedRecord(record);
      var metaInfo = _lockedGetMetaInfo() ?? CvMetaInfo();
      var lastChangeId = (metaInfo.lastChangeId.v ?? 0) + 1;
      var ref = SyncedDataSourceRef(
        store: record.record.v!.store.v,
        key: record.record.v!.key.v,
        syncId: record.syncId.v,
      );
      var existing = _lockedGetSourceRecord(ref);
      String syncId;
      if (existing == null) {
        syncId = '${++_lastSyncId}';
      } else {
        syncId = existing.syncId.v!;
      }
      // Make a copy
      var newRecord = CvSyncedSourceRecord()
        ..copyFrom(record)
        ..syncId.v = syncId
        ..syncTimestamp.v = Timestamp.now()
        ..syncChangeId.v = lastChangeId;
      _sourceRecordsBySyncId[syncId] = newRecord;
      _sourceRecordsByStoreAndKey[(
            newRecord.recordStore,
            newRecord.recordKey,
          )] =
          newRecord;
      _lockedPutMetaInfo(
        CvMetaInfo()
          ..copyFrom(metaInfo)
          ..lastChangeId.v = lastChangeId,
      );
      return newRecord;
    });
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) {
    return _lock.synchronized(() {
      var list = <CvSyncedSourceRecord>[];
      var all = sorterSourceRecords;
      var allLength = all.length;
      limit ??= allLength;
      afterChangeId ??= 0;
      for (var record in sorterSourceRecords) {
        if (record.syncChangeId.v! > afterChangeId!) {
          var add = true;
          if (record.isDeleted) {
            if (!(includeDeleted ?? false)) {
              add = false;
            }
          }
          if (add) {
            list.add(record);
            if (list.length >= limit!) {
              break;
            }
          }
        }
      }
      var lastChangeId = list.lastOrNull?.syncChangeId.v;

      return SyncedSourceRecordList(list, lastChangeId);
    });
  }

  @override
  @visibleForTesting
  Future<void> putRawRecord(CvSyncedSourceRecord record) async {
    return _lock.synchronized(() {
      var newRecord = CvSyncedSourceRecord()..copyFrom(record);
      var syncId = record.syncId.v!;
      _sourceRecordsBySyncId[syncId] = newRecord;
      _sourceRecordsByStoreAndKey[(
            newRecord.recordStore,
            newRecord.recordKey,
          )] =
          newRecord;
    });
  }
}
