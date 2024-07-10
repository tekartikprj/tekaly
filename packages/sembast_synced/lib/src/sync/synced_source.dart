import 'dart:async';

import 'package:meta/meta.dart';

import 'model/source_meta_info.dart';
import 'model/source_record.dart';

class SyncedDataSourceRef {
  /// Used first
  final String? syncId;

  /// Otherwise user store/key
  final String? store;
  final String? key;

  SyncedDataSourceRef({this.syncId, required this.store, required this.key});

  @override
  String toString() => 'syncId: $syncId, store: $store, key: $key';
}

/// Default mixin implementation.
mixin SyncedSourceDefaultMixin implements SyncedSource {
  void fixAndCheckPutSyncedRecord(SyncedSourceRecord record) {
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
  Stream<CvMetaInfoRecord?> onMetaInfo({Duration? checkDelay}) {
    checkDelay ??= Duration(minutes: 60);
    late StreamController<CvMetaInfoRecord?> controller;
    controller = StreamController<CvMetaInfoRecord?>(onListen: () async {
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
    }, onCancel: () {
      controller.close();
    });
    return controller.stream;
  }

  @override
  Future<CvMetaInfoRecord?> getMetaInfo() {
    throw UnimplementedError('SyncedSource.getMetaInfo');
  }

  @override
  Future<SyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef) {
    throw UnimplementedError('SyncedSource.getSourceRecord');
  }

  @override
  Future<SyncedSourceRecordList> getSourceRecordList(
      {int? afterChangeId, int? limit, bool? includeDeleted}) {
    throw UnimplementedError('SyncedSource.getSourceRecordList');
  }

  @override
  Future<CvMetaInfoRecord?> putMetaInfo(CvMetaInfoRecord info) {
    throw UnimplementedError('SyncedSource.putMetaInfo');
  }

  @override
  Future<void> putRawRecord(SyncedSourceRecord record) {
    throw UnimplementedError('SyncedSource.putRawRecord');
  }

  @override
  Future<SyncedSourceRecord?> putSourceRecord(SyncedSourceRecord record) {
    throw UnimplementedError('SyncedSource.putSourceRecord');
  }

  @override
  void close() {
    throw UnimplementedError('SyncedSource.close');
  }
}

abstract class SyncedSource {
  /// Sync id, change Id is generated or looked for if not given, store and key must be set
  Future<SyncedSourceRecord?> putSourceRecord(SyncedSourceRecord record);

  /// Get a record using
  Future<SyncedSourceRecord?> getSourceRecord(SyncedDataSourceRef sourceRef);

  /// Get the meta info
  Future<CvMetaInfoRecord?> getMetaInfo();

  /// Update meta info, source should check the existing for the worst case.
  @visibleForTesting
  Future<CvMetaInfoRecord?> putMetaInfo(CvMetaInfoRecord info);

  /// if [afterChangeId] is not null, only the update after it are fetched
  ///
  /// After calling this you should check meta info again to be sure the minChange did not change
  Future<SyncedSourceRecordList> getSourceRecordList(
      {int? afterChangeId, int? limit, bool? includeDeleted});

  @visibleForTesting
  Future<void> putRawRecord(SyncedSourceRecord record);

  /// Stream of meta info change
  /// If [checkDelay] is set, meta info will be checked every [checkDelay] duration
  /// On firestore if onSnapshot is supported this is unnecessary
  /// Default implementation will check every hour.
  Stream<CvMetaInfoRecord?> onMetaInfo({Duration? checkDelay});

  /// Close the source.
  void close();
}

extension SyncedSourceExt on SyncedSource {
  Future<SyncedSourceRecordList> getAllSourceRecordList(
      {int? afterChangeId, int? stepLimit, bool? includeDeleted}) async {
    var list = SyncedSourceRecordList(<SyncedSourceRecord>[], null);
    while (true) {
      var nextList = await getSourceRecordList(
          afterChangeId: afterChangeId,
          limit: stepLimit,
          includeDeleted: includeDeleted);
      var lastChangeId =
          nextList.lastChangeId ?? nextList.list.lastOrNull?.syncChangeId.v;
      list = SyncedSourceRecordList(
          [...list.list, ...nextList.list], lastChangeId ?? list.lastChangeId);
      if (nextList.isEmpty) {
        break;
      }
      afterChangeId = lastChangeId;
    }
    return list;
  }
}

class SyncedSourceRecordList {
  final List<SyncedSourceRecord> list;

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
