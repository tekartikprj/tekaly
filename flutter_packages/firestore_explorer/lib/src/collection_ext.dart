import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

extension CvCollectionReferenceExplorerExt<T extends CvFirestoreDocument>
    on CvCollectionReference<T> {
  /// Convert from raw reference.
  CvDocumentReference<T> get any => doc('*');
}
