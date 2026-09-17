import 'package:tekaly_synced_db_common/synced_db_common.dart';
import 'package:tekartik_common_utils/env_utils.dart';

/// Example timestamp used in the synchronizer tests.
///
/// Web steps might not handled microseconds
SyncedDbTimestamp exampleTimestamp1() =>
    kDartIsWeb ? SyncedDbTimestamp(1, 1000000) : SyncedDbTimestamp(1, 1000);
