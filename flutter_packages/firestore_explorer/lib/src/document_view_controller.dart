import 'dart:async';

import 'package:rxdart/rxdart.dart';

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

var forceNoTrackChanges = false;

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
  bool get supportTrackChanges =>
      firestore.service.supportsTrackChanges && !forceNoTrackChanges;
  StreamSubscription? _docSubscription;
  void _onListen() {
    _docSubscription ??= _stream.listen((event) {
      _docSubject.add(event);
    });
  }

  void _onCancel() {
    _docSubscription?.cancel();
    _docSubscription = null;
  }

  late final _docSubject =
      BehaviorSubject<T>(onListen: _onListen, onCancel: _onCancel);
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

  Stream<T> get _stream async* {
    if (supportTrackChanges) {
      yield* docRef.onSnapshot(firestore);
    } else {
      yield await docRef.get(firestore);
    }
  }

  /// Manual reload if not supporting track changes
  void reload() async {
    if (!supportTrackChanges) {
      var reading = await docRef.get(firestore);
      _docSubject.add(reading);
    }
  }

  @override
  Stream<T> get stream => _docSubject.stream;

  // T newDocument() => doc.cv();

  @override
  void close() {
    _docSubject.close();
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
