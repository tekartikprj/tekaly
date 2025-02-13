import 'package:flutter/foundation.dart';
import 'package:tekaly_firestore_explorer/src/import_firebase.dart';

abstract class DocumentClipboardData {
  factory DocumentClipboardData.empty() {
    return DocumentClipboardDataEmpty();
  }
  factory DocumentClipboardData.doc(CvFirestoreDocument document) {
    return DocumentClipboardDataDocument(document: document);
  }
  DocumentClipboardData();
}

class DocumentClipboardDataEmpty extends DocumentClipboardData {
  DocumentClipboardDataEmpty();
}

class DocumentClipboardDataDocument extends DocumentClipboardData {
  final CvFirestoreDocument document;

  DocumentClipboardDataDocument({required this.document});
}

class DocumentClipboardController extends ValueNotifier<DocumentClipboardData> {
  DocumentClipboardController() : super(DocumentClipboardData.empty());

  void addDoc(CvFirestoreDocument document) {
    value = DocumentClipboardData.doc(document);
  }

  CvFirestoreDocument? get doc {
    if (value is DocumentClipboardDataDocument) {
      return (value as DocumentClipboardDataDocument).document;
    }
    return null;
  }
}

final gDocumentClipboardController = DocumentClipboardController();
