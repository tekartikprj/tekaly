import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:tekaly_sdb_synced/src/sync/synced_sdb_export.dart';
import 'package:tekaly_sdb_synced/synced_sdb_internals.dart';

/// Io export extension.
extension SyncedSdbExportIoExt on SyncedSdb {
  /// Exports the database (tekaly format) to files in [dir].
  ///
  /// Creates `export.jsonl` and `export_meta.json`.
  Future<void> exportDatabase({required String dir}) async {
    var result = await exportInMemory();

    await Directory(dir).create(recursive: true);
    var file = File(join(dir, syncedSdbExportFilename));
    var fileMeta = File(join(dir, syncedSdbExportMetaFilename));

    await file.writeAsString(
      '${sdbExportLinesToJsonStringList(result.data).join('\n')}\n',
    );
    await fileMeta.writeAsString(jsonEncode(result.metaInfo.toMap()));
  }
}
