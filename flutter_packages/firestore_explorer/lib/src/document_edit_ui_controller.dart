import 'document_edit_controller.dart';
import 'document_view_ui_controller.dart';
import 'import_firebase.dart';

class FsDocumentFieldEditUiController<T extends CvFirestoreDocument>
    extends FsDocumentFieldEditControllerBase<T> {
  FsDocumentFieldEditUiController({
    required super.documentEditController,
    required super.parent,
    required super.field,
  });
}

abstract class FsDocumentEditUiController<T extends CvFirestoreDocument>
    implements FsDocumentViewUiController<T>, FsDocumentEditController<T> {
  factory FsDocumentEditUiController({
    required Firestore firestore,
    required CvDocumentReference<T> docRef,
  }) => _FsDocumentEditUiController(firestore: firestore, docRef: docRef);
}

class _FsDocumentEditUiController<T extends CvFirestoreDocument>
    extends FsDocumentEditControllerBase<T>
    implements FsDocumentEditUiController<T> {
  _FsDocumentEditUiController({
    required super.firestore,
    required super.docRef,
  });
}
