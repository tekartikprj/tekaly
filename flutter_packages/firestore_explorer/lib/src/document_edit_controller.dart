import 'package:tekaly_firestore_explorer/src/document_edit.dart';

import 'document_view_controller.dart';
import 'import_firebase.dart';

abstract class FsDocumentFieldEditController<T extends CvFirestoreDocument>
    implements FsDocumentFieldViewController<T> {
  FsDocumentFieldEditController? get parent;
  @override
  List<FsDocumentFieldEditController<T>> get subfields;
  @override
  CvField get field;
  FsDocumentEditController<T> get documentEditController;
  @override
  FsDocumentListFieldItemEditController<T> listFieldItem(int index);
  factory FsDocumentFieldEditController(
          {required FsDocumentEditController<T> documentEditController,
          required FsDocumentFieldEditController<T> parent,
          required CvField field}) =>
      _FsDocumentFieldEditController<T>(
          documentEditController: documentEditController,
          parent: parent,
          field: field);
}

abstract class FsDocumentListFieldItemEditController<
        T extends CvFirestoreDocument>
    implements FsDocumentListFieldItemViewController<T> {
  @override
  FsDocumentFieldEditController<T> get shadowFieldController;
  @override
  FsDocumentFieldEditController<T> get parent;

  factory FsDocumentListFieldItemEditController(
          {required FsDocumentFieldEditController<T> parent,
          required int index}) =>
      _FsDocumentListFieldItemEditController<T>(
          parent: parent, listIndex: index);
}

class _FsDocumentFieldEditController<T extends CvFirestoreDocument>
    extends FsDocumentFieldEditControllerBase<T>
    implements FsDocumentFieldEditController<T> {
  _FsDocumentFieldEditController(
      {required super.documentEditController,
      required super.parent,
      required super.field});
}

class _FsDocumentListFieldItemEditController<T extends CvFirestoreDocument>
    extends FsDocumentListFieldItemEditControllerBase<T>
    implements FsDocumentListFieldItemEditController<T> {
  _FsDocumentListFieldItemEditController({
    required super.parent,
    required super.listIndex,
  });
}

abstract class FsDocumentFieldEditControllerBase<T extends CvFirestoreDocument>
    implements FsDocumentFieldEditController<T> {
  @override
  final FsDocumentEditController<T> documentEditController;
  @override
  FsDocumentViewController<T> get documentViewController =>
      documentEditController;

  /// Start at 1, 0 being a document controller.
  @override
  int get level => parent == null ? 1 : parent!.level + 1;
  @override
  final FsDocumentFieldEditController? parent;
  @override
  final CvField field;
  FsDocumentFieldEditControllerBase({
    required this.documentEditController,
    required this.parent,
    required this.field,
  });

  @override
  List<FsDocumentFieldEditController<T>> get subfields {
    var field = this.field;

    if (field.isNotNull && field is CvModelField) {
      var subfields = field.v!.fields;
      return subfields.map((e) {
        return _FsDocumentFieldEditController<T>(
            documentEditController: documentEditController,
            field: e,
            parent: this);
      }).toList();
    } else {
      return <FsDocumentFieldEditControllerBase<T>>[];
    }
  }

  @override
  FsDocumentListFieldItemEditController<T> listFieldItem(int index) {
    var field = this.field;
    if (field is CvListField) {
      return FsDocumentListFieldItemEditController<T>(
          parent: this, index: index);
    }
    throw UnimplementedError();
  }
}

abstract class FsDocumentEditControllerBase<T extends CvFirestoreDocument>
    extends FsDocumentViewControllerBase<T>
    implements FsDocumentEditController<T> {
  bool get isNew => docRef.isNew;
  @override
  late T editedDocument;
  @override
  late final Future<T> futureEditedDocument = isNew
      ? Future<T>.value(editedDocument = cvTypeNewModel<T>(docRef.type))
      : stream.first.then((doc) {
          editedDocument = doc;
          return editedDocument;
        });
  FsDocumentEditControllerBase(
      {required super.firestore, required super.docRef});

  @override
  List<FsDocumentFieldEditController<T>> fieldsEditViews(T doc) {
    return doc.fields.map((e) {
      return _FsDocumentFieldEditController<T>(
          documentEditController: this, field: e, parent: null);
    }).toList();
  }
}

abstract class FsDocumentEditController<T extends CvFirestoreDocument>
    implements FsDocumentViewController<T> {
  factory FsDocumentEditController(
          {required Firestore firestore,
          required CvDocumentReference<T> docRef}) =>
      _FsDocumentEditController(firestore: firestore, docRef: docRef);

  Future<T> get futureEditedDocument;
  List<FsDocumentFieldEditController<T>> fieldsEditViews(T doc);

  T get editedDocument;
}

class _FsDocumentEditController<T extends CvFirestoreDocument>
    extends FsDocumentEditControllerBase<T>
    implements FsDocumentEditController<T> {
  _FsDocumentEditController({required super.firestore, required super.docRef});
}

class FsDocumentListFieldItemEditControllerBase<T extends CvFirestoreDocument>
    extends FsDocumentListFieldItemViewControllerBase<T>
    implements FsDocumentListFieldItemEditController<T> {
  @override
  FsDocumentFieldEditController<T> get shadowFieldController =>
      super.shadowFieldController as FsDocumentFieldEditController<T>;

  @override
  FsDocumentFieldEditController<T> get parent =>
      super.parent as FsDocumentFieldEditController<T>;

  @override
  FsDocumentFieldEditController<T> initShadowFieldController(
      {required FsDocumentViewController<T> documentViewController,
      required FsDocumentFieldViewController<T> parent,
      required CvField field}) {
    return FsDocumentFieldEditController<T>(
        documentEditController:
            documentViewController as FsDocumentEditController<T>,
        parent: parent as FsDocumentFieldEditController<T>,
        field: field);
  }

  FsDocumentListFieldItemEditControllerBase({
    required FsDocumentFieldEditController<T> parent,
    required super.listIndex,
  }) : super(parent: parent);
}
