// ignore_for_file: public_member_api_docs

import 'package:tekaly_synced_db_common/synced_db_common.dart';

export 'package:tekaly_synced_db_common/synced_db_common.dart'
    show SyncedSourceExportExt, SyncedSourceImportExt;

/// Tekaly export format encoding (`$timestamp`, `$blob`), see
/// [syncedDbValueToJsonEncodable].
Object? jsonEncodeSembastValueOrNull(Object? value) =>
    syncedDbValueToJsonEncodable(value);

/// Tekaly export format decoding, see [syncedDbValueFromJsonEncodable].
Object? jsonDecodeSembastValueOrNull(Object? value) =>
    syncedDbValueFromJsonEncodable(value);
