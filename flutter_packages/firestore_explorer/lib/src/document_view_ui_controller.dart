import 'document_view_controller.dart';
import 'import_firebase.dart';

class FsDocumentFieldViewUiController<T extends CvFirestoreDocument>
    extends FsDocumentFieldViewControllerBase<T> {
  FsDocumentFieldViewUiController(
      {required super.documentViewController,
      required super.parent,
      required super.field});
}

class FsDocumentViewUiController<T extends CvFirestoreDocument>
    extends FsDocumentViewControllerBase<T> {
  factory FsDocumentViewUiController(
          {required Firestore firestore,
          required CvDocumentReference<T> docRef}) =>
      _FsDocumentViewController(firestore: firestore, docRef: docRef);
}

class _FsDocumentViewController<T extends CvFirestoreDocument>
    extends FsDocumentViewControllerBase<T>
    implements FsDocumentViewUiController<T> {
  _FsDocumentViewController({required super.firestore, required super.docRef});
}
