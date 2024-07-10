import 'package:sembast/timestamp.dart' as sembast;
import 'package:tekaly_sembast_synced/src/sync/sembast_firestore_converter.dart';
import 'package:tekartik_firebase_firestore/firestore.dart' as firestore;
import 'package:test/test.dart';

void main() {
  group('sembast_firestore_converted', () {
    test('toSembast', () {
      expect(firestoreToSembast(firestore.Timestamp(1, 0)),
          sembast.Timestamp(1, 0));
      expect(firestoreToSembast([firestore.Timestamp(1, 0)]),
          [sembast.Timestamp(1, 0)]);
    });
    test('toFirestore', () {
      expect(sembastToFirestore(sembast.Timestamp(1, 0)),
          firestore.Timestamp(1, 0));
      expect(sembastToFirestore({'test': sembast.Timestamp(1, 0)}),
          {'test': firestore.Timestamp(1, 0)});
    });
  });
}
