import 'dart:async';

import 'import_firebase.dart';

const safePrefix = '79s9wGFU2PU2Xp1xigDx';

/// Never save that or use this outside of the library
const cvDocumentIdNew = '__${safePrefix}_new__';

/// User in memory only
const cvFieldNameNone = '__${safePrefix}_none__';

/// Nested list of raw values
extension DocumentViewCvListFieldExt<T extends Object?> on CvListField<T> {
  /// List create helper
  CvField<T> shadowField(T value) => CvField<T>(cvFieldNameNone, value);
}

/// Nested list of raw values
extension DocumentViewCvModelListFieldExt<T extends CvModel>
    on CvModelListField<T> {
  /// List create helper
  CvField<T> shadowModelField(T value) =>
      CvModelField.builder(name, builder: create)..v = value;
}

abstract class FsDocumentListFieldItemViewController<
    T extends CvFirestoreDocument> {
  FsDocumentFieldViewController<T> get shadowFieldController;
  FsDocumentFieldViewController<T> get parent;
  int get listLevel;
  CvField get listField;

  /// Optional index for sub list items
  int get listIndex;

  factory FsDocumentListFieldItemViewController(
          {required FsDocumentFieldViewController<T> parent,
          required int index}) =>
      _FsDocumentListFieldItemViewController<T>(
          parent: parent, listIndex: index);
}

class _FsDocumentListFieldItemViewController<T extends CvFirestoreDocument>
    extends FsDocumentListFieldItemViewControllerBase<T>
    implements FsDocumentListFieldItemViewController<T> {
  _FsDocumentListFieldItemViewController(
      {required super.parent, required super.listIndex});
}

abstract class FsDocumentFieldViewController<T extends CvFirestoreDocument> {
  FsDocumentViewController<T> get documentViewController;
  int get level;
  CvField get field;

  /// Optional index for sub list items

  List<FsDocumentFieldViewController<T>> get subfields;
  factory FsDocumentFieldViewController(
          {required FsDocumentViewController<T> documentViewController,
          required FsDocumentFieldViewController<T> parent,
          required CvField field}) =>
      _FsDocumentFieldViewController<T>(
          documentViewController: documentViewController,
          parent: parent,
          field: field);

  /// Create a controller of a list field
  FsDocumentListFieldItemViewController<T> listFieldItem(int index) =>
      FsDocumentListFieldItemViewController<T>(parent: this, index: index);
}

class _FsDocumentFieldViewController<T extends CvFirestoreDocument>
    extends FsDocumentFieldViewControllerBase<T>
    implements FsDocumentFieldViewController<T> {
  _FsDocumentFieldViewController(
      {required super.documentViewController,
      required super.parent,
      required super.field});
}

class FsDocumentFieldViewControllerBase<T extends CvFirestoreDocument>
    implements FsDocumentFieldViewController<T> {
  @override
  final FsDocumentViewController<T> documentViewController;

  /// Start at 1, 0 being a document controller.
  @override
  int get level => parent == null ? 1 : parent!.level + 1;
  final FsDocumentFieldViewController? parent;
  @override
  final CvField field;

  FsDocumentFieldViewControllerBase({
    required this.documentViewController,
    required this.parent,
    required this.field,
  });

  @override
  List<FsDocumentFieldViewController<T>> get subfields {
    var field = this.field;

    if (field.isNotNull && field is CvModelField) {
      var subfields = field.v!.fields;
      return subfields.where((element) => element.isNotNull).map((e) {
        return FsDocumentFieldViewControllerBase<T>(
            documentViewController: documentViewController,
            field: e,
            parent: this);
      }).toList();
    } else {
      return <FsDocumentFieldViewControllerBase<T>>[];
    }
  }

  @override
  FsDocumentListFieldItemViewController<T> listFieldItem(int index) {
    var field = this.field;
    if (field is CvListField) {
      return FsDocumentListFieldItemViewController<T>(
          parent: this, index: index);
    }
    throw UnimplementedError();
  }
}

class FsDocumentListFieldItemViewControllerBase<T extends CvFirestoreDocument>
    implements FsDocumentListFieldItemViewController<T> {
  @override
  late final FsDocumentFieldViewController<T> shadowFieldController =
      _doInitShadowField();

  /// Start at 1, 0 being a document controller.
  @override
  int get listLevel => parent.level + 1;
  @override
  final FsDocumentFieldViewController<T> parent;

  @override
  CvListField get listField => parent.field as CvListField;

  CvField get shadowField => shadowFieldController.field;

  @override
  final int listIndex;

  FsDocumentFieldViewController<T> _doInitShadowField() {
    var listField = this.listField;
    var list = listField.v!;
    CvField shadowField;
    var value = list[listIndex];
    if (value == null) {
      shadowField = CvField(cvFieldNameNone, null);
    } else if (listField is CvModelListField) {
      shadowField = listField.shadowModelField(list[listIndex] as CvModel);
    } else {
      shadowField = listField.shadowField(list[listIndex]);
    }
    return initShadowFieldController(
        documentViewController: parent.documentViewController,
        parent: parent,
        field: shadowField);
  }

  FsDocumentFieldViewController<T> initShadowFieldController(
      {required FsDocumentViewController<T> documentViewController,
      required FsDocumentFieldViewController<T> parent,
      required CvField field}) {
    return FsDocumentFieldViewController(
        documentViewController: parent.documentViewController,
        parent: parent,
        field: field);
  }

  FsDocumentListFieldItemViewControllerBase({
    required this.parent,
    required this.listIndex,
  });
}

class FsDocumentViewControllerBase<T extends CvFirestoreDocument>
    implements FsDocumentViewController<T> {
  @override
  final Firestore firestore;
  @override
  final CvDocumentReference<T> docRef;

  bool get isRoot => docRef.path == cvRootDocumentReference.path;
  @override
  List<FsDocumentFieldViewController<T>> fieldsViews(T doc) {
    if (isRoot) {
      return <FsDocumentFieldViewController<T>>[];
    }
    return doc.fields.where((element) => element.isNotNull).map((e) {
      return FsDocumentFieldViewControllerBase<T>(
          documentViewController: this, field: e, parent: null);
    }).toList();
  }

  FsDocumentViewControllerBase({required this.firestore, required this.docRef});

  StreamController<T>? _controller;
  StreamSubscription<T>? _subscription;

  StreamController<T> get streamController =>
      _controller ??= StreamController<T>.broadcast(onListen: () {
        if (isRoot) {
          _controller!.add(CvFirestoreMapDocument() as T);
        } else {
          _subscription = _stream.listen((event) {
            _controller!.add(event);
          });
        }
      }, onCancel: () {
        _subscription?.cancel();
        _subscription = null;
      });

  Stream<T> get _stream async* {
    if (firestore.service.supportsTrackChanges) {
      yield* docRef.onSnapshot(firestore);
    } else {
      yield await docRef.get(firestore);
    }
  }

  @override
  Stream<T> get stream => streamController.stream;

  // T newDocument() => doc.cv();

  @override
  void close() {
    _controller?.close();
  }
}

class FieldReference {
  final List<Object> paths;

  FieldReference(this.paths);

  @override
  String toString() {
    return 'FieldReference{path: $paths}';
  }
}

abstract class FsDocumentViewController<T extends CvFirestoreDocument> {
  CvDocumentReference get docRef;
  Firestore get firestore;
  List<FsDocumentFieldViewController<T>> fieldsViews(T doc);
  factory FsDocumentViewController(
          {required Firestore firestore,
          required CvDocumentReference<T> docRef}) =>
      _FsDocumentViewController(firestore: firestore, docRef: docRef);
  Stream<T> get stream;
  void close();
}

class _FsDocumentViewController<T extends CvFirestoreDocument>
    extends FsDocumentViewControllerBase<T>
    implements FsDocumentViewController<T> {
  _FsDocumentViewController({required super.firestore, required super.docRef});
}

Map<Type, List<FieldReference>> documentViewReferenceMap = {};

/// String is a path. empty for root
Map<String, List<CvCollectionReference>> _documentViewCollectionMap = {};
Map<String, List<CvDocumentReference>> _documentViewDocumentMap = {};

void documentViewAddRootCollections(List<CvCollectionReference> list) {
  var keyPath = '';
  _documentViewCollectionMap[keyPath] = list;
}

void documentViewAddCollections(List<CvCollectionReference> list) {
  for (var coll in list) {
    documentViewAddCollection(coll);
  }
}

void documentViewAddCollection(CvCollectionReference coll) {
  var parent = coll.parent;
  String keyPath;
  if (parent == null) {
    keyPath = '';
  } else {
    var docPath = parent.path;
    var genericPath = firestorePathGetGenericPath(docPath);
    keyPath = genericPath;
  }
  var list = _documentViewCollectionMap[keyPath] ??= <CvCollectionReference>[];
  list.add(coll);
}

void documentViewAddDocument(CvDocumentReference doc) {
  var genericPath = firestorePathGetGenericPath(doc.path);
  var keyPath = firestoreDocPathGetParent(genericPath);
  var list = _documentViewDocumentMap[keyPath] ??= <CvDocumentReference>[];
  list.add(doc);
}

void documentViewAddDocuments(List<CvDocumentReference> list) {
  for (var doc in list) {
    documentViewAddDocument(doc);
  }
}

List<CvCollectionReference> documentViewListCollections(String path) {
  var genericPath = firestorePathGetGenericPath(path);
  var list = _documentViewCollectionMap[genericPath];
  if (list == null) {
    return <CvCollectionReference>[];
  }
  return list
      .map((e) => e.withPath(firestorePathGetChild(path, e.id)))
      .toList();
}

List<CvDocumentReference> documentViewListDocuments(String path) {
  var genericPath = firestorePathGetGenericPath(path);
  var list = _documentViewDocumentMap[genericPath];
  if (list == null) {
    return <CvDocumentReference>[];
  }
  return list
      .map((e) => e.withPath(firestorePathGetChild(path, e.id)))
      .toList();
}
