// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:sembast/timestamp.dart';

import 'package:tekartik_app_cv_sembast/app_cv_sembast.dart';

/// Entity in the database.
class DbEntity extends DbStringRecordBase {
  final name = CvField<String>('name');
  final timestamp = CvField<Timestamp>('timestamp');

  @override
  List<CvField> get fields => [name, timestamp];
}

var dbEntityStoreRef = cvStringStoreFactory.store<DbEntity>('entity');

/// Excluded from sync by default
var dbLocalEntityStoreRef = cvStringStoreFactory.store<DbEntity>(
  'entity_local',
);
String get dbEntityStoreName => dbEntityStoreRef.name;
