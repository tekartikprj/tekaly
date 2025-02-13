import 'package:cv/cv_json.dart';

class ApiChangeRef extends CvModelBase {
  /// If available
  final syncId = CvField<String>('syncId');
  // Mandatory
  final store = CvField<String>('store');
  final key = CvField<String>('key');

  @override
  List<CvField> get fields => <CvField>[syncId, store, key];
}

class ApiChange extends ApiChangeRef {
  final changeNum = CvField<int>('changeNum');
  final data = CvField<Model>('data'); // null means deletion
  /// Optional timestamp (not set in put/get request but present in list)
  /// If set in put, overrides server timestamp
  final timestamp = CvField<String>('timestamp');
  @override
  late final List<CvField> fields = <CvField>[
    ...super.fields,
    changeNum,
    data,
    timestamp,
  ];

  bool get isDeleted => data.v == null;
}

class ApiPutChangeRequest extends ApiChange {
  /// Target location in destination, typically same for all changes
  final target = CvField<String>('target');
  @override
  List<CvField> get fields => [target, ...super.fields];
}

class ApiPutChangeResponse extends ApiChange {}

class ApiPutChangesRequest extends CvModelBase {
  /// Target location in destination, same for all changes
  final target = CvField<String>('target');
  final changes = CvModelListField<ApiChange>('changes');
  @override
  late final List<CvField> fields = <CvField>[target, changes];
}

class ApiPutChangesResponse extends CvModelBase {
  final changeNums = CvListField<int>('changeNums');
  @override
  late final List<CvField> fields = <CvField>[changeNums];
}

class ApiGetChangesRequest extends CvModelBase {
  final target = CvField<String>('target');

  /// Exclusive min, changes are at least +1 (or 1 if null)
  final afterChangeNum = CvField<int>('afterChangeNum');
  final includeDeleted = CvField<bool>('includeDeleted');
  final limit = CvField<int>('limit'); // overr
  @override
  late final List<CvField> fields = <CvField>[
    target,
    afterChangeNum,
    includeDeleted,
    limit,
  ]; // ide the server limit (200 but can change)
}

class ApiGetChangesResponse extends CvModelBase {
  /// Can be empty
  final changes = CvModelListField<ApiChange>('changes');

  /// True if more are available, false to stop
  ///
  /// Can be null, apps could rely on the changes size for now if not set.
  ///
  /// If set, this value should be used
  final shouldContinue = CvField<bool>('shouldContinue');

  /// If available, last in the list read
  final lastChangeNum = CvField<int>('lastChangeNum');

  /// Never null
  final syncInfo = CvModelField<ApiSyncInfo>('syncInfo');

  @override
  late final fields = [changes, shouldContinue, lastChangeNum, syncInfo];
}

class ApiGetChangeRequest extends ApiChangeRef {
  final target = CvField<String>('target');
  @override
  late final List<CvField> fields = <CvField>[target, ...super.fields]; // ide the server limit (200 but can change)
}

class ApiGetChangeResponse extends ApiChange {}

class ApiSyncInfo extends CvModelBase {
  final minIncrementalChangeNum = CvField<int>('minIncrementalChangeNum');
  final lastChangeNum = CvField<int>('lastChangeNum');
  final version = CvField<int>('version');
  @override
  late final fields = [version, minIncrementalChangeNum, lastChangeNum];
}

class ApiGetSyncInfoResponse extends ApiSyncInfo {}

class ApiGetSyncInfoRequest extends CvModelBase {
  /// Target location in destination
  final target = CvField<String>('target');
  @override
  List<CvField<Object?>> get fields => <CvField>[target];
}

class ApiPutSyncInfoResponse extends ApiSyncInfo {}

class ApiPutSyncInfoRequest extends ApiSyncInfo {
  /// Target location in destination
  final target = CvField<String>('target');
  @override
  List<CvField<Object?>> get fields => <CvField>[target, ...super.fields];
}
