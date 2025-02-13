import 'package:cv/cv.dart';
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_common_utils/log_format.dart';

/// Stat event list result
class StatEventListResult {
  /// event list
  final List<StatEvent> events;

  /// Next cursor
  final Object? nextCursor;

  /// Constructor
  StatEventListResult({required this.events, required this.nextCursor});
}

/// Stat event list query
class StatEventListQuery {
  /// The cursor (from previous result.nextCursor)
  final Object? cursor;

  /// min date time
  final DateTime? minTimestamp;

  /// max date time
  final DateTime? maxTimestamp;

  /// Default is datetime ascending
  final bool descending;

  /// Optional name, otherwise get all events
  final String? name;

  /// maxCount (default to 1000)
  final int? maxCount;

  /// Constructor
  StatEventListQuery({
    this.name,
    this.maxCount,
    bool? descending,
    this.cursor,

    /// inclusive
    this.minTimestamp,

    /// exclusive
    this.maxTimestamp,
  }) : descending = descending ?? false;

  /// New query with curor
  StatEventListQuery withCursor(Object nextCursor) {
    return StatEventListQuery(
      name: name,
      maxCount: maxCount,
      descending: descending,
      cursor: nextCursor,
      minTimestamp: minTimestamp,
      maxTimestamp: maxTimestamp,
    );
  }
}

/// A stat client
abstract class StatClient {
  /// Client id, typically one per app
  String get clientId;

  /// Close the client
  Future<void> close();

  /// Add event
  Future<StatEvent> addEvent(StatEvent event);

  /// Add events
  Future<List<StatEvent>> addEvents(List<StatEvent> event);

  /// Get event by id
  Future<StatEvent?> getEvent(String id);

  /// Get an event list
  Future<StatEventListResult> getEventList(StatEventListQuery query);
}

/// A stat event.
abstract class StatEvent {
  /// Null for unsaved event
  String? get idOrNull;

  /// Generated on save
  String get id;

  /// timestamp of the event
  DateTime get timestamp;

  /// Event name
  String get name;

  /// Data
  Object get data;

  /// Data as map
  Model get dataAsMap;

  /// Stat event from client
  factory StatEvent({
    DateTime? timestamp,
    required String name,
    required Object data,
  }) => StatEventBase(timestamp: timestamp, name: name, data: data);
}

/// Stat event mixin
mixin StatEventMixin implements StatEvent {
  /// Data as map
  @override
  Model get dataAsMap => asModel(data.asOrNull<Map>()!);
  @override
  String get id => idOrNull!;
  @override
  int get hashCode => idOrNull?.hashCode ?? 0;
  @override
  bool operator ==(Object other) {
    if (other is StatEvent) {
      return other.idOrNull == idOrNull;
    }
    return super == other;
  }

  @override
  String toString() =>
      '${idOrNull != null ? '$id: ' : ''}${timestamp.toIso8601String()} $name ${logFormat(data)}';
}

/// Stat event base
class StatEventBase with StatEventMixin {
  @override
  late final DateTime timestamp;
  @override
  final String name;
  @override
  final Object data;

  /// Overridable id
  @override
  String? idOrNull;

  /// Constructor
  StatEventBase({DateTime? timestamp, required this.name, required this.data}) {
    this.timestamp = timestamp ?? DateTime.now();
  }
}

/// Base client
abstract class StatClientBase implements StatClient {
  @override
  final String clientId;

  /// Base client
  StatClientBase({required this.clientId});

  @mustCallSuper
  @override
  Future<void> close() async {}
}
