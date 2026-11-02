import 'package:cv/cv.dart';

import 'model/source_record.dart';

/// The records of a synced source split by a field of their value (such as a
/// user id), so that a client downloads only its own records.
///
/// A download optimization, not a security: every client may still read
/// every record of the source.
///
/// Every source writing to the location must name the same [field] (with no
/// [value] to read all the records, an admin): a deleted record then keeps
/// this field, and the sources reading its partition see the delete.
///
/// On Firestore, reading a partition needs a composite index on the data
/// collection: `record.value.<field>` then `syncChangeId`, both ascending.
///
/// Limitation: a record moved to another partition (its [field] changed) is
/// not deleted from the clients of its former partition, they keep it.
class SyncedSourcePartition {
  /// The field of the record value holding the partition (a key of the
  /// value, not a path).
  final String field;

  /// The partition read, all the records when null.
  final Object? value;

  /// A partition by [field], reading only the records whose [field] is
  /// [value] (all of them when null).
  const SyncedSourcePartition({required this.field, this.value});

  /// True when only one partition is read.
  bool get isFiltered => value != null;

  /// True when [record] belongs to the partition read (always when not
  /// [isFiltered]).
  bool matches(CvSyncedSourceRecord record) =>
      !isFiltered || record.record.v?.value.v?[field] == value;

  /// The value of a deleted record replacing [existing]: only its [field],
  /// null when it has none (no partition to tell).
  Model? deletedValue(CvSyncedSourceRecord? existing) {
    var fieldValue = existing?.record.v?.value.v?[field];
    if (fieldValue == null) {
      return null;
    }
    return newModel()..[field] = fieldValue;
  }

  /// [record] to write, a deleted one keeping the [field] of [existing].
  ///
  /// [record] is returned as is when not deleted or when [existing] has no
  /// partition, otherwise a copy.
  CvSyncedSourceRecord recordToPut(
    CvSyncedSourceRecord record,
    CvSyncedSourceRecord? existing,
  ) {
    if (!record.isDeleted) {
      return record;
    }
    var value = deletedValue(existing);
    if (value == null) {
      return record;
    }
    var data = record.record.v!;
    return CvSyncedSourceRecord()
      ..copyFrom(record)
      ..record.v = (CvSyncedSourceRecordData()
        ..store.v = data.store.v
        ..key.v = data.key.v
        ..deleted.v = true
        ..value.v = value);
  }

  @override
  String toString() =>
      'SyncedSourcePartition($field${isFiltered ? ': $value' : ''})';
}
