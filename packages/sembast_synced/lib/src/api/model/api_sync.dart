import 'package:cv/cv_json.dart';

/// Api change ref
class ApiChangeRef extends CvModelBase {
  /// If available
  final syncId = CvField<String>('syncId');

  /// Mandatory store
  final store = CvField<String>('store');

  /// Mandatory key
  final key = CvField<String>('key');

  @override
  List<CvField> get fields => <CvField>[syncId, store, key];
}

/// Api change
class ApiChange extends ApiChangeRef {
  /// Change num
  final changeNum = CvField<int>('changeNum');

  /// Changed data, null means deletion
  final data = CvField<Model>('data');

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
}

/// Api change extension
extension ApiChangeExt on ApiChange {
  /// True for deleted record
  bool get isDeleted => data.v == null;
}

/// Put change request
class ApiPutChangeRequest extends ApiChange {
  /// Target location in destination, typically same for all changes
  final target = CvField<String>('target');
  @override
  List<CvField> get fields => [target, ...super.fields];
}

/// Put change response
class ApiPutChangeResponse extends ApiChange {}

/// Put changes request
class ApiPutChangesRequest extends CvModelBase {
  /// Target location in destination, same for all changes
  final target = CvField<String>('target');

  /// List of changes
  final changes = CvModelListField<ApiChange>('changes');
  @override
  late final List<CvField> fields = <CvField>[target, changes];
}

/// Put changes response
class ApiPutChangesResponse extends CvModelBase {
  /// Change nums
  final changeNums = CvListField<int>('changeNums');
  @override
  late final List<CvField> fields = <CvField>[changeNums];
}

class ApiGetChangesRequest extends CvModelBase {
  /// Target location in destination.
  final target = CvField<String>('target');

  /// Exclusive min, changes are at least +1 (or 1 if null)
  final afterChangeNum = CvField<int>('afterChangeNum');

  /// Include deleted records.
  final includeDeleted = CvField<bool>('includeDeleted');

  /// Limit the number of changes.
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
