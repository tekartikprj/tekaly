import 'package:flutter/material.dart';
import 'package:tekartik_firebase_ui_firestore/firebase_ui_firestore.dart';

import 'document_edit.dart';
import 'document_view.dart';
import 'document_view_controller.dart';
import 'import_common.dart';
import 'import_firebase.dart';
import 'mapping.dart';

class FsDocumentListScreen extends StatefulWidget {
  final Firestore firestore;
  final CvQueryReference query;
  const FsDocumentListScreen(
      {super.key, required this.query, required this.firestore});

  @override
  State<FsDocumentListScreen> createState() => _FsDocumentListScreenState();
}

class _FsDocumentListScreenState extends State<FsDocumentListScreen> {
  Firestore get firestore => widget.firestore;
  CvQueryReference get query => widget.query;

  @override
  Widget build(BuildContext context) {
    var fixedDocuments =
        documentViewListDocuments(query.collectionReference.path);
    //devPrint('query: $query ($fixedDocuments)');
    var fixedDocumentsIds = fixedDocuments.map((e) => e.id).toSet();
    return Scaffold(
      appBar: AppBar(
          title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Document list ${getTypeName(query.type)}'),
          Text(
            query.collectionReference.path,
            style: const TextStyle(fontSize: 10),
          )
        ],
      )),
      body: (fixedDocuments.isEmpty)
          ? buildItemList(fixedDocumentsIds)
          : ListView(
              children: [
                ListView(
                  shrinkWrap: true,
                  children: [
                    ...fixedDocuments.map((docRef) {
                      return DocumentListItem(
                          model: docRef.cv(),
                          firestore: firestore,
                          docRef: docRef);
                    })
                  ],
                ),
                buildItemList(fixedDocumentsIds, shrinkWrap: true),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await goToFsDocumentEditScreen(context,
              firestore: firestore,
              doc: widget.query.collectionReference.doc(cvDocumentIdNew));
          // reload if needed
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  FutureBuilder<Query> buildItemList(Set<String> fixedDocumentsIds,
      {bool shrinkWrap = false}) {
    return FutureBuilder(
        future: query.rawASync(firestore),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container();
          }
          var rawQuery = snapshot.data!;
          return FirestoreListView(
            shrinkWrap: shrinkWrap,
            query: rawQuery,
            itemBuilder: (BuildContext context, DocumentSnapshot doc) {
              try {
                CvFirestoreDocument model;

                // Try unique specific doc builder.
                var ref = documentViewGetDocument(doc.ref.path);
                if (ref.type != CvFirestoreDocument) {
                  model = ref.cv();
                } else {
                  model = ref.cvType(query.type);
                }

                // Exclude already added documents
                if (fixedDocumentsIds.contains(model.id)) {
                  return Container();
                }
                return DocumentListItem(
                    model: model, firestore: firestore, docRef: ref);
              } catch (e) {
                // ignore: avoid_print
                print('Error on ${query.type} ${doc.ref.path}: $e');
                return ListTile(
                  title: Text('Error on ${query.type} ${doc.ref.path}'),
                  subtitle: Text('Error building on ${doc.data}: $e'),
                );
              }
            },
          );
        });
  }
}

class DocumentListItem extends StatelessWidget {
  final CvDocumentReference docRef;
  const DocumentListItem({
    super.key,
    required this.model,
    required this.firestore,
    required this.docRef,
  });

  final CvFirestoreDocument model;
  final Firestore firestore;

  @override
  Widget build(BuildContext context) {
    var refs = documentViewReferenceMap[docRef.type] ??= [];
    return ListTile(
      title: Text(model.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...refs.map((fr) {
            var field = model.fieldAtPath(fr.paths);
            if (field != null) {
              return Text('${field.name}: ${field.value}');
            }
            return Container();
          })
        ],
      ),
      onTap: () {
        goToFsDocumentViewScreen(context, firestore: firestore, doc: docRef);
      },
    );
  }
}

Future<void> goToFsDocumentListScreen(BuildContext context,
    {required Firestore firestore, required CvQueryReference query}) async {
  documentViewInit();
  await Navigator.of(context).push<Object?>(MaterialPageRoute(
      builder: (_) => FsDocumentListScreen(
            query: query,
            firestore: firestore,
          )));
}
