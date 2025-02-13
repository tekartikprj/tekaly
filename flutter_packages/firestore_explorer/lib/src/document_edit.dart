import 'package:cv/utils/value_utils.dart';
import 'package:flutter/material.dart';
import 'package:tekaly_firestore_explorer/src/document_clipboard_controller.dart';
import 'package:tekaly_firestore_explorer/src/mapping.dart';
import 'package:tekaly_firestore_explorer/src/utils.dart';

import 'document_edit_controller.dart';
import 'document_edit_ui_controller.dart';
import 'document_view_controller.dart';
import 'import_firebase.dart';

extension CvDocumentReferenceEditExt on CvDocumentReference {
  bool get isNew => id == cvDocumentIdNew;
}

InputDecoration buildInputDecoration({required String labelText}) {
  return InputDecoration(
    labelText: labelText,
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4.0)),
    ),
  );
}

class FsDocumentEdit extends StatefulWidget {
  final FsDocumentEditController controller;

  const FsDocumentEdit({super.key, required this.controller});

  @override
  State<FsDocumentEdit> createState() => _FsDocumentEditState();
}

class _FsDocumentEditState extends State<FsDocumentEdit> {
  FsDocumentEditController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.controller.docRef.path),
              Text(getTypeName(widget.controller.docRef.type)),
              FutureBuilder(
                future: controller.futureEditedDocument,
                builder: (_, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    );
                  }
                  var doc = snapshot.data!;
                  return Column(
                    children:
                        controller
                            .fieldsEditViews(doc)
                            .map((e) => FsDocumentFieldEdit(controller: e))
                            .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class FsDocumentFieldEdit extends StatefulWidget {
  final FsDocumentFieldEditController controller;

  const FsDocumentFieldEdit({super.key, required this.controller});

  @override
  State<FsDocumentFieldEdit> createState() => _FsDocumentFieldEditState();
}

class _FsDocumentFieldEditState extends State<FsDocumentFieldEdit>
    with DocumentValueEditStateMixin<FsDocumentFieldEdit> {
  FsDocumentFieldEditController get controller => widget.controller;

  @override
  CvField get field => controller.field;

  @override
  Widget build(BuildContext context) {
    return buildMixin(context);
  }

  @override
  FsDocumentFieldEditController<CvFirestoreDocument> get fieldController =>
      controller;
}

Future<void> goToFsDocumentEditScreen(
  BuildContext context, {
  required Firestore firestore,
  required CvDocumentReference doc,
}) async {
  documentViewInit();
  await Navigator.of(context).push<Object?>(
    MaterialPageRoute(
      builder: (_) => FsDocumentEditScreen(doc: doc, firestore: firestore),
    ),
  );
}

mixin DocumentValueEditStateMixin<T extends StatefulWidget> on State<T> {
  final inEdit = ValueNotifier<bool>(false);

  FsDocumentFieldEditController get fieldController;

  CvField get field => fieldController.field;

  int get level => fieldController.level;

  CvListField get listField => field as CvListField;
  TextEditingController? textEditingController;

  Widget buildMixin(BuildContext context, {Widget? leading}) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(left: 16.0 * level),
          child: ValueListenableBuilder<bool>(
            valueListenable: inEdit,
            builder: (context, snapshot, _) {
              if (snapshot) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller:
                        textEditingController ??= TextEditingController(
                          text: field.value?.toString() ?? '',
                        ),
                    decoration: buildInputDecoration(labelText: field.name),
                    onSubmitted: (value) {
                      setState(() {
                        inEdit.value = false;
                      });
                    },
                    onChanged: editSaveField,
                  ),
                );
              }
              String? subtitleText;
              var value = field.value;
              var valueType = value.runtimeType;
              var typeName = field.getTypeName();

              var titleText = field.name;
              if (field is CvModelField) {
                subtitleText = typeName;
              } else if (field is CvListField) {
                subtitleText = typeName;
              } else {
                if (valueType.isBasicType) {
                  titleText = value.toString();
                } else {
                  subtitleText = typeName;
                }
                //subtitleText = field.value.toString();
              }

              return Column(
                children: [
                  ListTile(
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (field.hasValue)
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                field.clear();
                              });
                            },
                          ),
                        if (field.hasValue)
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              _edit();
                            },
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.create_outlined),
                            onPressed: () {
                              _edit();
                            },
                          ),
                      ],
                    ),
                    title: Text(titleText),
                    subtitle: subtitleText == null ? null : Text(subtitleText),
                    onTap: () {
                      _edit();

                      /*
                    showDialog(
                        context: context,
                        builder: (_) {
                          return AlertDialog(
                            title: Text(field.name),
                            content: FormReport(
                              form: field.form,
                              data: widget.controller.parent.data,
                              onChanged: (data) {
                                widget.controller.parent.data = data;
                              },
                            ),
                          );
                        });*/
                    },
                  ),
                  if (field is CvListField && field.hasValue)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: Column(
                        children: [
                          for (var (index, item)
                              in (field as CvListField).v!.indexed)
                            ListTile(
                              title: Text(item.toString()),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  setState(() {
                                    (field as CvListField).v!.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          ListTile(
                            onTap: () {
                              var field = this.field;
                              if (field is CvModelListField) {
                                // devPrint('Creating model list field');

                                setState(() {
                                  field.v!.add(field.create({}));
                                });
                              } else if (field is CvListField) {
                                setState(() {
                                  field.v!.add(field.createDefaultValue());
                                });
                              }
                            },
                            title: const Text('Add'),
                            trailing: const Icon(Icons.add),
                          ),
                          if (field is CvListField)
                            ...listField.v!.indexed.map(((e) {
                              var index = e.$1;
                              //var item = e.$2;
                              //return Container();

                              return FsDocumentListFieldItemEdit(
                                controller: fieldController.listFieldItem(
                                  index,
                                ),
                              );
                            })),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        ...fieldController.subfields.map(
          (e) => FsDocumentFieldEdit(controller: e),
        ),
      ],
    );
  }

  void editSaveField(String? value) {
    field.fromBasicTypeValue(value);
  }

  void _edit() {
    if (field.isBasicType) {
      _editText();
    } else if (field is CvModelField) {
      // devPrint('Creating model field');

      setState(() {
        if (!field.hasValue) {
          field.v = (field as CvModelField).create({});
        }
      });
    } else if (field is CvListField) {
      // devPrint('Creating model list field');

      setState(() {
        if (!field.hasValue) {
          field.v = (field as CvListField).createList();
        }
      });
    } else {
      if (field.name == cvFieldNameNone &&
          (field.value?.runtimeType.isBasicType ?? false)) {
        setState(() {
          field.v = field.value;
        });
      } else {
        // ignore: avoid_print
        print('Unknown field $field');
      }
    }
    // devPrint(field.type);
  }

  void _editText() {
    inEdit.value = true;
  }
}

/// Screen
class FsDocumentEditScreen extends StatefulWidget {
  final Firestore firestore;
  final CvDocumentReference doc;

  const FsDocumentEditScreen({
    super.key,
    required this.doc,
    required this.firestore,
  });

  @override
  State<FsDocumentEditScreen> createState() => _FsDocumentEditScreenState();
}

class _FsDocumentEditScreenState extends State<FsDocumentEditScreen> {
  Firestore get firestore => widget.firestore;

  CvDocumentReference get docRef => widget.doc;

  bool get isNew => controller.docRef.isNew;

  TextEditingController? idController;

  @override
  void initState() {
    if (isNew) {
      idController = TextEditingController();
    }
    super.initState();
  }

  late final controller = FsDocumentEditUiController(
    firestore: firestore,
    docRef: docRef,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document edit'),
        actions: [
          IconButton(
            onPressed: () async {
              var doc = gDocumentClipboardController.doc;
              snack('doc: $doc');
              if (doc != null) {
                var existing = await controller.futureEditedDocument;

                snack('existing: $existing');
                setState(() {
                  existing.copyFrom(doc);
                });
              }
            },
            icon: const Icon(Icons.paste),
          ),
        ],
      ),
      body: ListView(
        children: [
          Column(
            children: [
              if (isNew)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 16.0),
                      TextField(
                        controller: idController,
                        decoration: buildInputDecoration(labelText: 'id'),
                      ),
                      const SizedBox(height: 16.0),
                    ],
                  ),
                ),
              FsDocumentEdit(controller: controller),
              const SizedBox(height: 80),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // devPrint('onSave');
          var fsDoc = controller.editedDocument;
          if (isNew) {
            var id = idController!.text;
            var localDocRef = docRef;

            if (id.isNotEmpty) {
              localDocRef = docRef.withId(id);
            }

            if (id.isEmpty) {
              await localDocRef.parent.add(firestore, fsDoc);
            } else {
              await localDocRef.set(firestore, fsDoc);
            }
          } else {
            var localDocRef = docRef;
            await localDocRef.set(firestore, fsDoc);
            // devPrint(controller.editedDocument);
            // devPrint(controller.stream);
          }
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: const Icon(Icons.save),
      ),
    );
  }
}

class FsDocumentListFieldItemEdit extends StatefulWidget {
  final FsDocumentListFieldItemEditController controller;

  const FsDocumentListFieldItemEdit({super.key, required this.controller});

  @override
  State<FsDocumentListFieldItemEdit> createState() =>
      _FsDocumentListFieldItemEditState();
}

class _FsDocumentListFieldItemEditState
    extends State<FsDocumentListFieldItemEdit>
    with DocumentValueEditStateMixin<FsDocumentListFieldItemEdit> {
  @override
  Widget build(BuildContext context) {
    return buildMixin(context, leading: Text('${widget.controller.listIndex}'));
  }

  @override
  FsDocumentFieldEditController<CvFirestoreDocument> get fieldController =>
      widget.controller.shadowFieldController;
}
