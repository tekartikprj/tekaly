// ignore_for_file: public_member_api_docs

import 'package:cv/cv.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

import 'synced_db_common_lib.dart';

typedef _Key = (String store, String key);

/// The data of a memory source, shared by its partitions.
class _SyncedSourceMemoryData {
  final lock = Lock();
  CvMetaInfo? metaInfo;
  final sourceRecordsBySyncId = <String, CvSyncedSourceRecord>{};
  final sourceRecordsByStoreAndKey = <_Key, CvSyncedSourceRecord>{};
}

class SyncedSourceMemory
    with SyncedSourceDefaultMixin, SyncedSourceFailureMixin
    implements SyncedSource {
  final _SyncedSourceMemoryData _data;

  /// The partition of the records (a user id field), if any: only the
  /// records of its value are read, a deleted record keeps its field.
  final SyncedSourcePartition? partition;

  Lock get _lock => _data.lock;
  CvMetaInfo? get _metaInfo => _data.metaInfo;
  set _metaInfo(CvMetaInfo? metaInfo) => _data.metaInfo = metaInfo;
  Map<String, CvSyncedSourceRecord> get _sourceRecordsBySyncId =>
      _data.sourceRecordsBySyncId;
  Map<_Key, CvSyncedSourceRecord> get _sourceRecordsByStoreAndKey =>
      _data.sourceRecordsByStoreAndKey;

  SyncedSourceMemory({SyncedSourcePartition? partition})
    : this._(_SyncedSourceMemoryData(), partition);

  SyncedSourceMemory._(this._data, this.partition) {
    initBuilders();
  }

  /// The same source (same records) with [partition], the clients of one
  /// location reading different partitions.
  SyncedSourceMemory withPartition(SyncedSourcePartition? partition) =>
      SyncedSourceMemory._(_data, partition);
  @override
  Future<void> close() async {}

  Iterable<CvSyncedSourceRecord> get sorterSourceRecords =>
      _sourceRecordsBySyncId.values.toList()
        ..sort((r1, r2) => r1.syncChangeId.v!.compareTo(r2.syncChangeId.v!));
  @override
  Future<CvMetaInfo?> getMetaInfo() {
    return _lock.synchronized(() {
      checkFailure(SyncedSourceOperation.getMetaInfo);
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
      checkFailure(SyncedSourceOperation.putMetaInfo);
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
      checkFailure(SyncedSourceOperation.getSourceRecord);
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
      checkFailure(SyncedSourceOperation.putSourceRecord);
      fixAndCheckPutSyncedRecord(record);
      var metaInfo = _lockedGetMetaInfo() ?? CvMetaInfo();
      var lastChangeId = (metaInfo.lastChangeId.v ?? 0) + 1;
      var store = record.record.v!.store.v!;
      var key = record.record.v!.key.v!;
      var ref = SyncedDataSourceRef(
        store: store,
        key: key,
        syncId: record.syncId.v,
      );
      var existing = _lockedGetSourceRecord(ref);
      String syncId;
      if (existing == null) {
        syncId = syncedDbStoreKeySyncId(store, key);
      } else {
        syncId = existing.syncId.v!;
      }
      // Make a copy, a deleted record keeping the partition field.
      var newRecord = CvSyncedSourceRecord()
        ..copyFrom(partition?.recordToPut(record, existing) ?? record)
        ..syncId.v = syncId
        ..syncTimestamp.v = SyncedDbTimestamp.now()
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
      checkFailure(SyncedSourceOperation.getSourceRecordList);
      var list = <CvSyncedSourceRecord>[];
      var all = sorterSourceRecords;
      var allLength = all.length;
      limit ??= allLength;
      afterChangeId ??= 0;
      // Like firestore, the last change id read, a skipped deleted record
      // included: a list of deleted records only still moves the cursor.
      int? lastChangeId;
      for (var record in sorterSourceRecords) {
        // Like a firestore query on the partition: the other records are
        // not read at all.
        if (!(partition?.matches(record) ?? true)) {
          continue;
        }
        if (record.syncChangeId.v! > afterChangeId!) {
          lastChangeId = record.syncChangeId.v;
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
      return SyncedSourceRecordList(list, lastChangeId);
    });
  }

  @override
  @visibleForTesting
  Future<void> putRawRecord(CvSyncedSourceRecord record) async {
    return _lock.synchronized(() {
      checkFailure(SyncedSourceOperation.putRawRecord);
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
