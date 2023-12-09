import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tekaly_firestore_explorer/src/import_common.dart';
import 'package:tekaly_firestore_explorer/src/utils.dart';
import 'package:tekartik_firebase_ui_firestore/firebase_ui_firestore.dart';

import 'document_clipboard_controller.dart';
import 'document_edit.dart';
import 'document_view_controller.dart';
import 'import_firebase.dart';

class FsRootView extends StatefulWidget {
  final Firestore firestore;
  const FsRootView({super.key, required this.firestore});

  @override
  State<FsRootView> createState() => _FsRootViewState();
}

class _FsRootViewState extends State<FsRootView> {
  @override
  Widget build(BuildContext context) {
    var collections = documentViewListCollections('');
    return Column(children: [
      ...collections.map((e) => FsCollectionListItem(
            firestore: widget.firestore,
            collRef: e,
          )),
    ]);
  }
}

class FsDocumentView extends StatefulWidget {
  final FsDocumentViewController controller;
  const FsDocumentView({super.key, required this.controller});

  @override
  State<FsDocumentView> createState() => _FsDocumentViewState();
}

class _FsDocumentViewState extends State<FsDocumentView> {
  Firestore get firestore => controller.firestore;
  FsDocumentViewController get controller => widget.controller;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${widget.controller.docRef.type}'),
          ],
        ),
        Text(widget.controller.docRef.path.nonEmpty() ?? '/'),
        StreamBuilder(
            stream: controller.stream,
            builder: (_, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                );
              }
              var doc = snapshot.data!;
              var collections = documentViewListCollections(doc.path);
              return Column(children: [
                ...controller
                    .fieldsViews(doc)
                    .map((e) => FsDocumentFieldView(controller: e)),
                ...collections.map((e) => FsCollectionListItem(
                      firestore: firestore,
                      collRef: e,
                    )),
              ]);
            })
      ],
    );
  }
}

class FsCollectionListItem extends StatelessWidget {
  final CvCollectionReference collRef;
  const FsCollectionListItem({
    super.key,
    required this.firestore,
    required this.collRef,
  });

  final Firestore firestore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
        title: Text(collRef.type.toString()),
        subtitle: Text(collRef.id),
        onTap: () {
          goToFsDocumentListScreen(context,
              firestore: firestore, query: collRef.query());
        });
  }
}

class FsDocumentFieldView extends StatefulWidget {
  final FsDocumentFieldViewController controller;
  const FsDocumentFieldView({super.key, required this.controller});

  @override
  State<FsDocumentFieldView> createState() => _FsDocumentFieldViewState();
}

mixin DocumentValueViewStateMixin<T extends StatefulWidget> on State<T> {
  FsDocumentFieldViewController get fieldController;
  CvField get field => fieldController.field;
  int get level => fieldController.level;
  CvListField get listField => field as CvListField;

  Widget buildMixin(BuildContext context, {Widget? leading}) {
    var isListField = field is CvListField;
    var showContent = field is! CvModelField && !isListField;
    String? subtitle = field.type.toString();
    var name = field.name;
    String? valueLabel;

    if (name == cvFieldNameNone) {
      name = subtitle;
      subtitle = null;
    } else {
      if (showContent) {
        if (field.hasValue) {
          valueLabel = field.value?.toString();
        } else {
          valueLabel = '<unset>';
        }
        subtitle = valueLabel;
      }
      if (field is CvListField) {
        subtitle = '${field.type}';
      } else {
        if (field.hasValue) {
          valueLabel = field.value.toString();
        } else {
          valueLabel = '<unset>';
        }
      }
      //subtitle = valueLabel;
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(left: level * 16.0),
          child: Column(
            children: [
              ListTile(
                  leading: leading,
                  dense: !showContent,
                  title: Text(name),
                  subtitle: subtitle != null ? Text(subtitle) : null,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: subtitle ?? ''));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Copied')));
                  }),
              if (field is CvListField)
                ...listField.v!.indexed.map(((e) {
                  var index = e.$1;
                  //var item = e.$2;

                  return FsDocumentListFieldItemView(
                      controller: fieldController.listFieldItem(index));
                }))
            ],
          ),
        ),
        ...fieldController.subfields
            .map((e) => FsDocumentFieldView(controller: e))
      ],
    );
  }
}

class _FsDocumentFieldViewState extends State<FsDocumentFieldView>
    with DocumentValueViewStateMixin<FsDocumentFieldView> {
  FsDocumentFieldViewController get controller => widget.controller;
  @override
  CvField get field => widget.controller.field;

  @override
  CvListField get listField => field as CvListField;
  @override
  Widget build(BuildContext context) {
    return buildMixin(context);
  }

  @override
  FsDocumentFieldViewController get fieldController => controller;
}

class FsDocumentListFieldItemView extends StatefulWidget {
  final FsDocumentListFieldItemViewController controller;
  const FsDocumentListFieldItemView({super.key, required this.controller});

  @override
  State<FsDocumentListFieldItemView> createState() =>
      _FsDocumentListFieldItemViewState();
}

class _FsDocumentListFieldItemViewState
    extends State<FsDocumentListFieldItemView>
    with DocumentValueViewStateMixin<FsDocumentListFieldItemView> {
  @override
  Widget build(BuildContext context) {
    return buildMixin(context, leading: Text('${widget.controller.listIndex}'));
  }

  @override
  FsDocumentFieldViewController<CvFirestoreDocument> get fieldController =>
      widget.controller.shadowFieldController;
}

Future<void> goToFsDocumentViewScreen(BuildContext context,
    {required Firestore firestore, required CvDocumentReference doc}) async {
  await Navigator.of(context).push<Object?>(MaterialPageRoute(
      builder: (_) => FsDocumentViewScreen(
            doc: doc,
            firestore: firestore,
          )));
}

Future<void> goToFsDocumentRootScreen(BuildContext context,
    {required Firestore firestore}) async {
  await Navigator.of(context).push<Object?>(MaterialPageRoute(
      builder: (_) => FsDocumentRootScreen(
            firestore: firestore,
          )));
}

class FsDocumentViewScreen extends StatefulWidget {
  final Firestore firestore;
  final CvDocumentReference doc;
  const FsDocumentViewScreen(
      {super.key, required this.doc, required this.firestore});

  @override
  State<FsDocumentViewScreen> createState() => _FsDocumentViewScreenState();
}

class _FsDocumentViewScreenState extends State<FsDocumentViewScreen> {
  Firestore get firestore => widget.firestore;
  CvDocumentReference get doc => widget.doc;
  late final controller =
      FsDocumentViewController(firestore: firestore, docRef: doc);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document view'),
        actions: [
          IconButton(
              onPressed: () async {
                var doc = await controller.stream.first;
                gDocumentClipboardController.addDoc(doc);
                snack('Copied $doc');
              },
              icon: const Icon(Icons.copy))
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [FsDocumentView(controller: controller)],
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await goToFsDocumentEditScreen(context,
              firestore: firestore, doc: doc);
          (controller as FsDocumentViewControllerBase).reload();
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}

class FsDocumentRootScreen extends StatefulWidget {
  final Firestore firestore;

  const FsDocumentRootScreen({super.key, required this.firestore});

  @override
  State<FsDocumentRootScreen> createState() => _FsDocumentRootScreenState();
}

class _FsDocumentRootScreenState extends State<FsDocumentRootScreen> {
  Firestore get firestore => widget.firestore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Root view')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [FsRootView(firestore: firestore)],
            ),
          )
        ],
      ),
    );
  }
}

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
    return Scaffold(
      appBar: AppBar(
          title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Document list ${query.type}'),
          Text(
            query.collectionReference.path,
            style: const TextStyle(fontSize: 10),
          )
        ],
      )),
      body: fixedDocuments.isNotEmpty
          ? ListView(
              children: [
                ...fixedDocuments.map((docRef) {
                  return DocumentListItem(
                      model: docRef.cv(), firestore: firestore, docRef: docRef);
                })
              ],
            )
          : FutureBuilder(
              future: query.rawASync(firestore),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container();
                }
                var rawQuery = snapshot.data!;
                return FirestoreListView(
                  query: rawQuery,
                  itemBuilder: (BuildContext context, DocumentSnapshot doc) {
                    var model = doc.cvType(query.type);

                    return DocumentListItem(
                        model: model,
                        firestore: firestore,
                        docRef: query.collectionReference.doc(model.id));
                  },
                );
              }),
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
  await Navigator.of(context).push<Object?>(MaterialPageRoute(
      builder: (_) => FsDocumentListScreen(
            query: query,
            firestore: firestore,
          )));
}
