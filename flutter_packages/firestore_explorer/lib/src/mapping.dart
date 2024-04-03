import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

Map<Type, String> _typeNames = {};

void documentViewAddTypeName(Type type, String name) {
  addTypeName(type, name);
}

void documentViewAddTypeNames(Map<Type, String> map) {
  _typeNames.addAll(map);
}

void addTypeName(Type type, String name) {
  _typeNames[type] = name;
}

String getTypeName(Type type) {
  var name = _typeNames[type];
  name ??= type.toString();
  return name;
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
  if (list.contains(coll)) {
    return;
  }
  list.add(coll);
}

void documentViewAddDocument(CvDocumentReference doc) {
  var genericPath = firestorePathGetGenericPath(doc.path);
  var keyPath = firestoreDocPathGetParent(genericPath);
  var list = _documentViewDocumentMap[keyPath] ??= <CvDocumentReference>[];
  if (list.contains(doc)) {
    return;
  }
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
