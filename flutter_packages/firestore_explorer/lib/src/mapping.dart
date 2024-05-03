import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

Map<Type, String> _typeNames = {
  String: 'String',
  int: 'int',
  double: 'double',
  bool: 'bool',
  num: 'num'
};

void documentViewAddTypeName(Type type, String name) {
  addTypeName(type, name);
}

void documentViewAddTypeNames(Map<Type, String> map) {
  _typeNames.addAll(map);
}

void addTypeName(Type type, String name) {
  _typeNames[type] = name;
}

String getTypeName(Type type) => _getTypeName(type);

String _getTypeName(Type type) {
  var name = _typeNames[type];
  name ??= '[$type]';
  return name;
}

extension CvListFieldLocalExt<T> on CvListField<T> {
  String getItemTypeName() {
    return _getTypeName(itemType);
  }

  T createDefaultValue() {
    if (itemType == String) {
      return '' as T;
    } else if (itemType == int) {
      return 0 as T;
    } else if (itemType == double) {
      return 0.0 as T;
    } else if (itemType == bool) {
      return false as T;
    } else if (itemType == num) {
      return 0 as T;
    }
    throw UnsupportedError('Unsupported type $itemType');
  }
}

extension CvFieldLocalExt on CvField {
  String getTypeName() {
    var self = this;
    if (self.isBasicType) {
      return _getTypeName(self.type);
    } else if (self is CvModelField) {
      return _getTypeName(self.type);
    } else if (self is CvListField) {
      return 'List<${self.getItemTypeName()}>';
    }
    return _getTypeName(type);
  }
}

Map<Type, List<FieldReference>> documentViewReferenceMap = {};

/// String is a path. empty for root
Map<String, List<CvCollectionReference>> _documentViewCollectionMap = {};
Map<String, List<CvDocumentReference>> _documentViewDocumentMap = {};

var documentViewFirestoreRootKeyPath = '';

void documentViewAddRootCollections(List<CvCollectionReference> list) {
  var keyPath = documentViewFirestoreRootKeyPath;
  _documentViewCollectionMap[keyPath] = list;
}

void documentViewClearData() {
  _documentViewCollectionMap.clear();
  _documentViewDocumentMap.clear();
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

/// Path is a document path
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

/// Path is a collection path
CvCollectionReference documentViewGetCollection(String path) {
  return documentViewGetCollectionOrNull(path) ?? CvCollectionReference(path);
}

/// Path is a collection path
CvCollectionReference? documentViewGetCollectionOrNull(String path) {
  var parentPath =
      firestoreCollPathGetParent(path) ?? documentViewFirestoreRootKeyPath;
  var collId = firestorePathGetId(path);
  var genericPath = firestorePathGetGenericPath(parentPath);
  var list = _documentViewCollectionMap[genericPath];
  if (list != null) {
    for (var coll in list) {
      if (coll.id == collId) {
        return coll.withPath(path);
      }
    }
  }
  return null;
}

/// List the known reference documents at a given path
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

CvDocumentReference documentViewGetDocument(String path) {
  return documentViewGetDocumentOrNull(path) ??
      CvDocumentReference<CvFirestoreDocument>(path);
}

CvDocumentReference? documentViewGetDocumentOrNull(String path) {
  var parent = firestoreDocPathGetParent(path);
  var docId = firestorePathGetId(path);
  var genericPath = firestorePathGetGenericPath(parent);
  var docList = _documentViewDocumentMap[genericPath];

  if (docList != null) {
    for (var doc in docList) {
      if (doc.id == docId) {
        return doc.withPath(path);
      }
    }
  }

  var coll = documentViewGetCollectionOrNull(parent);
  return coll?.doc(docId).withPath(path);
}

void documentViewInit() {
  cvFirestoreAddBuilder<CvFirestoreDocument>((_) => CvFirestoreMapDocument());
  cvAddConstructor(CvFirestoreMapDocument.new);
  documentViewAddTypeNames({
    CvFirestoreDocument: 'CvFirestoreDocument',
    CvFirestoreMapDocument: 'CvFirestoreMapDocument'
  });
}
