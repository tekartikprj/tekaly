import 'dart:async';

import 'package:cv/cv.dart';
import 'package:meta/meta.dart';

import 'model/source_meta_info.dart';
import 'model/source_record.dart';

/// Synced data source reference
class SyncedDataSourceRef {
  /// Used first
  final String? syncId;

  /// Otherwise user store/key
  final String? store;

  /// Key
  final String? key;

  /// Constructor
  SyncedDataSourceRef({this.syncId, required this.store, required this.key});

  @override
  String toString() => 'syncId: $syncId, store: $store, key: $key';
}

/// Common implementation
String syncedDbStoreKeySyncId(String store, String key) {
  return '$store|$key';
}

String _refSyncId(SyncedDataSourceRef ref) {
  return ref.syncId ?? syncedDbStoreKeySyncId(ref.store!, ref.key!);
}

extension SyncedDataSourceRefExt on SyncedDataSourceRef {
  /// Common source sync id
  String get _sourceSyncId => _refSyncId(this);
  SyncedDataSourceRef fixedSourceSyncId() =>
      SyncedDataSourceRef(syncId: _sourceSyncId, store: store, key: key);
}

/// Default mixin implementation.
mixin SyncedSourceDefaultMixin implements SyncedSource {
  void initBuilders() {
    cvAddConstructor(CvSyncedSourceRecord.new);
    cvAddConstructor(CvMetaInfo.new);
    cvAddConstructor(CvSyncedSourceRecordData.new);
  }

  /// Fix and check
  void fixAndCheckPutSyncedRecord(CvSyncedSourceRecord record) {
    if (record.record.v!.store.v == null) {
      throw ArgumentError.notNull(record.record.v!.store.name);
    }
    if (record.record.v!.key.v == null) {
      throw ArgumentError.notNull(record.record.v!.key.name);
    }
    // Set delete field if not done
    record.record.v!.deleted.v ??= false;
  }

  @override
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay}) {
    checkDelay ??= const Duration(minutes: 60);
    late StreamController<CvMetaInfo?> controller;
    controller = StreamController<CvMetaInfo?>(
      onListen: () async {
        while (true) {
          var info = await getMetaInfo();
          if (!controller.isClosed) {
            controller.add(info);
          } else {
            break;
          }
          await Future<void>.delayed(checkDelay!);
          if (controller.isClosed) {
            break;
          }
        }
      },
      onCancel: () {
        controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<CvMetaInfo?> getMetaInfo() {
    throw UnimplementedError('SyncedSource.getMetaInfo');
  }

  @override
  Future<CvSyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef) {
    throw UnimplementedError('SyncedSource.getSourceRecord');
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  }) {
    throw UnimplementedError('SyncedSource.getSourceRecordList');
  }

  @override
  Future<CvMetaInfo> putMetaInfo(CvMetaInfo info) {
    throw UnimplementedError('SyncedSource.putMetaInfo');
  }

  @override
  Future<void> putRawRecord(CvSyncedSourceRecord record) {
    throw UnimplementedError('SyncedSource.putRawRecord');
  }

  @override
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record) {
    throw UnimplementedError('SyncedSource.putSourceRecord');
  }

  @override
  Future<void> close() async {
    // Do nothing by default
  }
}

abstract class SyncedSource {
  /// Sync id, change Id is generated or looked for if not given, store and key must be set
  Future<CvSyncedSourceRecord> putSourceRecord(CvSyncedSourceRecord record);

  /// Get a record using
  Future<CvSyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef);

  /// Get the meta info
  Future<CvMetaInfo?> getMetaInfo();

  /// Update meta info, source should check the existing for the worst case.
  @visibleForTesting
  Future<CvMetaInfo?> putMetaInfo(CvMetaInfo info);

  /// if [afterChangeId] is not null, only the update after it are fetched
  ///
  /// After calling this you should check meta info again to be sure the minChange did not change
  Future<SyncedSourceRecordList> getSourceRecordList({
    int? afterChangeId,
    int? limit,
    bool? includeDeleted,
  });

  /// Put a raw record on the storage
  @visibleForTesting
  Future<void> putRawRecord(CvSyncedSourceRecord record);

  /// Stream of meta info change
  /// If [checkDelay] is set, meta info will be checked every [checkDelay] duration
  /// On firestore if onSnapshot is supported this is unnecessary
  /// Default implementation will check every hour.
  Stream<CvMetaInfo?> onMetaInfo({Duration? checkDelay});

  /// Close the source.
  Future<void> close();
}

extension SyncedSourceExt on SyncedSource {
  Future<SyncedSourceRecordList> getAllSourceRecordList({
    int? afterChangeId,
    int? stepLimit,
    bool? includeDeleted,
  }) async {
    var list = SyncedSourceRecordList(<CvSyncedSourceRecord>[], null);
    while (true) {
      var nextList = await getSourceRecordList(
        afterChangeId: afterChangeId,
        limit: stepLimit,
        includeDeleted: includeDeleted,
      );
      var lastChangeId =
          nextList.lastChangeId ?? nextList.list.lastOrNull?.syncChangeId.v;
      list = SyncedSourceRecordList([
        ...list.list,
        ...nextList.list,
      ], lastChangeId ?? list.lastChangeId);
      if (nextList.isEmpty) {
        break;
      }
      afterChangeId = lastChangeId;
    }
    return list;
  }
}

class SyncedSourceRecordList {
  final List<CvSyncedSourceRecord> list;

  /// Last change id.
  final int? lastChangeId;

  SyncedSourceRecordList(this.list, this.lastChangeId);

  bool get isNotEmpty => list.isNotEmpty;

  int get length => list.length;

  bool get isEmpty => list.isEmpty;

  @override
  String toString() =>
      'SyncedSourceRecordList(${list.length} item(s), lastChangeId: $lastChangeId)';
}
