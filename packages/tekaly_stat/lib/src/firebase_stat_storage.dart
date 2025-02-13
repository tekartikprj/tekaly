import 'package:tekaly_stat/stat_client.dart';
import 'package:tekaly_stat/stat_storage.dart';
import 'package:tekartik_app_cv_firestore/app_cv_firestore.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' as fb;
import 'package:tekartik_firebase_storage/storage.dart' as fb;

const _defaultMaxCount = 100;

/// Options for [StatStorageFirebase].
class StatStorageOptionsFirebase {
  /// Root doc
  final fb.DocumentReference fsRootDoc;

  /// Firestore instance.
  final fb.Firestore firestore;

  /// Firebase storage instance.
  final fb.FirebaseStorage? storage;

  /// Constructor.
  StatStorageOptionsFirebase({
    required this.firestore,
    this.storage,
    required this.fsRootDoc,
  });
}

/// Firebase implementation of [StatStorage].
class StatStorageFirebase implements StatStorage {
  /// Options.
  final StatStorageOptionsFirebase options;

  /// Constructor.
  StatStorageFirebase({required this.options});
}

class _FsStatEvent extends CvFirestoreDocumentBase {
  final timestamp = CvField<Timestamp>('timestamp');
  final name = CvField<String>('name');
  final data = CvField<Object>('data');
  @override
  CvFields get fields => [timestamp, name, data];

  _FsStatEvent();

  /// From event
  _FsStatEvent.fromEvent(StatEvent statEvent) {
    timestamp.v = Timestamp.fromDateTime(statEvent.timestamp);
    name.v = statEvent.name;
    data.v = statEvent.data;
  }

  /// To stat event
  StatEvent toEvent() => _StatEventFirebase(fbStatEvent: this);
}

final _fsStatEventModel = _FsStatEvent();

/// Firebase client
class StatClientFirebase extends StatClientBase {
  /// Storage
  final StatStorageFirebase storage;

  fb.Firestore get _firestore => storage.options.firestore;

  /// Constructor
  StatClientFirebase({required this.storage, required super.clientId}) {
    cvAddConstructors([_FsStatEvent.new]);
  }

  CvCollectionReference<_FsStatEvent> get _clientCollection =>
      storage.options.fsRootDoc.cv().collection<_FsStatEvent>(clientId);
  @override
  Future<StatEvent> addEvent(StatEvent event) async {
    var fsEvent = await _clientCollection.add(
      _firestore,
      _FsStatEvent.fromEvent(event),
    );
    return fsEvent.toEvent();
  }

  @override
  Future<StatEvent?> getEvent(String id) async {
    var fsEvent = await _clientCollection.doc(id).get(_firestore);
    return fsEvent.exists ? fsEvent.toEvent() : null;
  }

  @override
  Future<StatEventListResult> getEventList(StatEventListQuery query) async {
    var fbQuery = _clientCollection
        .query()
        .orderBy(_fsStatEventModel.timestamp.name, descending: query.descending)
        .orderById(descending: query.descending);
    if (query.name != null) {
      fbQuery = fbQuery.where(
        _fsStatEventModel.name.name,
        isEqualTo: query.name,
      );
    }
    if (query.minTimestamp != null) {
      fbQuery = fbQuery.where(
        _fsStatEventModel.timestamp.name,
        isGreaterThanOrEqualTo: Timestamp.fromDateTime(query.minTimestamp!),
      );
    }
    if (query.maxTimestamp != null) {
      fbQuery = fbQuery.where(
        _fsStatEventModel.timestamp.name,
        isLessThan: Timestamp.fromDateTime(query.maxTimestamp!),
      );
    }
    if (query.cursor != null) {
      var cursor = query.cursor as _CursorFirebase;
      fbQuery = fbQuery.startAfter(values: [cursor.timestamp, cursor.id]);
    }
    fbQuery = fbQuery.limit(query.maxCount ?? _defaultMaxCount);

    var fsEvents = await fbQuery.get(_firestore);
    if (fsEvents.isEmpty) {
      return StatEventListResult(
        events: <StatEvent>[],
        nextCursor: query.cursor,
      );
    } else {
      var events = fsEvents.map((fsEvent) => fsEvent.toEvent()).toList();
      var last = fsEvents.last;
      return StatEventListResult(
        events: events,
        nextCursor: _CursorFirebase(timestamp: last.timestamp.v!, id: last.id),
      );
    }

    // TODO: implement getEventList
  }

  @override
  Future<List<StatEvent>> addEvents(List<StatEvent> events) async {
    var list = <StatEvent>[];
    for (var event in events) {
      list.add(await addEvent(event));
    }
    return list;
  }
}

class _StatEventFirebase with StatEventMixin {
  final _FsStatEvent fbStatEvent;
  _StatEventFirebase({required this.fbStatEvent});

  @override
  String get id => fbStatEvent.id;
  @override
  Object get data => fbStatEvent.data.v!;

  @override
  String get name => fbStatEvent.name.v!;

  @override
  DateTime get timestamp => fbStatEvent.timestamp.v!.toDateTime();

  @override
  String? get idOrNull => id;
}

class _CursorFirebase {
  final Timestamp timestamp;
  final String id;

  _CursorFirebase({required this.timestamp, required this.id});
}
