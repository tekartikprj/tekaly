import 'package:collection/collection.dart';

import 'synced_db_export_info.dart';

/// The first line of a tekaly export, which says what the format is.
const syncedDbExportHeaderLine = <String, Object?>{
  'tekaly_export': 1,
  'version': 1,
};

/// Comparing two exports by what they hold rather than line by line.
///
/// Two exports of the same content — one taken from a local synced database,
/// the other from the source it syncs with — agree on the records and disagree
/// on the meta line: the change id, the timestamp and the source version are
/// each side's own bookkeeping. These helpers compare what is meant to match.
///
/// ```dart
/// var local = await syncedSdb.exportInMemory();
/// var remote = await source.exportInMemory();
/// expect(local.findContentDifference(remote), isNull);
/// ```
extension SyncedDbExportInfoCompareExt on SyncedDbExportInfo {
  /// The lines without the meta one: the header, the stores and the records.
  List<Object> get contentLines => [
    if (data.isNotEmpty) data.first,
    // The meta line always sits second, see the export helpers.
    ...data.skip(2),
  ];

  /// The store names the export holds, in the order it lists them.
  List<String> get storeNames => [
    for (var line in data.skip(1))
      if (line is Map && line['store'] is String) line['store'] as String,
  ];

  /// The records, `{store: {key: value}}`, which is what two exports of the
  /// same content must agree on however they order them.
  Map<String, Map<String, Object?>> get recordsByStore {
    var records = <String, Map<String, Object?>>{};
    String? store;
    for (var line in data.skip(1)) {
      if (line is Map) {
        var name = line['store'];
        if (name is String) {
          store = name;
          records[store] ??= <String, Object?>{};
        }
      } else if (line is List && line.length >= 2 && store != null) {
        records[store]!['${line[0]}'] = line[1];
      }
    }
    return records;
  }

  /// How many records the export holds, every store together.
  int get recordCount =>
      recordsByStore.values.fold(0, (count, records) => count + records.length);

  /// True when [other] holds the same records, whatever each side's meta line
  /// says.
  bool matchesContent(SyncedDbExportInfo other) =>
      findContentDifference(other) == null;

  /// What differs from [other], null when nothing does.
  ///
  /// The message names the first store, key or value that disagrees, so a
  /// failing comparison says what to look at rather than printing two
  /// exports.
  String? findContentDifference(SyncedDbExportInfo other) {
    const equality = DeepCollectionEquality();
    var mine = recordsByStore;
    var theirs = other.recordsByStore;

    var myStores = mine.keys.toSet();
    var theirStores = theirs.keys.toSet();
    var missing = myStores.difference(theirStores);
    if (missing.isNotEmpty) {
      return 'store ${missing.first} is missing on the other side';
    }
    var extra = theirStores.difference(myStores);
    if (extra.isNotEmpty) {
      return 'store ${extra.first} is only on the other side';
    }

    for (var store in myStores) {
      var myRecords = mine[store]!;
      var theirRecords = theirs[store]!;
      var missingKeys = myRecords.keys.toSet().difference(
        theirRecords.keys.toSet(),
      );
      if (missingKeys.isNotEmpty) {
        return '$store/${missingKeys.first} is missing on the other side';
      }
      var extraKeys = theirRecords.keys.toSet().difference(
        myRecords.keys.toSet(),
      );
      if (extraKeys.isNotEmpty) {
        return '$store/${extraKeys.first} is only on the other side';
      }
      for (var key in myRecords.keys) {
        if (!equality.equals(myRecords[key], theirRecords[key])) {
          return '$store/$key differs: '
              '${myRecords[key]} vs ${theirRecords[key]}';
        }
      }
    }
    return null;
  }
}
