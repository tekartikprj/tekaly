---
name: tekaly-firestore-explorer-browse-documents
description: >-
  Use when adding a debug/admin firestore browser to a flutter app with
  tekaly_firestore_explorer: goToFsDocumentRootScreen,
  goToFsDocumentViewScreen, goToFsDocumentListScreen, goToFsDocumentEditScreen,
  FsDocumentView, FsDocumentEdit, FsDocumentViewController,
  FsDocumentEditController, documentViewAddCollections,
  documentViewAddDocuments, documentViewAddTypeNames,
  documentViewReferenceMap, FieldReference, and the `any` collection extension
  for typed cv firestore documents.
---

# Browse and edit firestore documents (tekaly_firestore_explorer)

`tekaly_firestore_explorer` is an experimental, developer facing firestore
explorer: a few flutter screens that list, view and edit `cv` typed firestore
documents (`CvFirestoreDocument`), on top of `tekartik_firebase_firestore` and
`tekartik_app_cv_firestore`. It is a debug/admin tool, not an end user UI.

## Guidelines

* This package is not on pub.dev, depend on it with a git dependency:

  ```yaml
  dependencies:
    tekaly_firestore_explorer:
      git:
        url: https://github.com/tekartikprj/tekaly
        path: flutter_packages/firestore_explorer
      version: '>=0.1.0'
  ```

* A single import is enough:
  `package:tekaly_firestore_explorer/firestore_explorer.dart`. It re-exports
  `package:cv/cv.dart`, `package:tekartik_app_cv_firestore/app_cv_firestore.dart`
  and `package:tekartik_firebase_firestore/firestore.dart`, so `CvField`,
  `CvCollectionReference`, `CvDocumentReference`, `Firestore` and
  `cvAddConstructors` all come from it.
* Register the document builders first (`cvAddConstructors([MyDoc.new, ...])`,
  once at startup): the explorer builds typed models from the declared
  references, and falls back to an untyped `CvFirestoreMapDocument` for any
  path it does not know.
* Declare the schema so the explorer knows what lives where, typically at
  startup, right after the constructors:
  * `documentViewAddCollections([...])` for `CvCollectionReference`s (root and
    sub-collections),
  * `documentViewAddDocuments([...])` for individual `CvDocumentReference`s
    (fixed documents such as a `settings` doc).
  * A sub-collection under any parent document is described with the `any`
    extension (`CvCollectionReferenceExplorerExt`): `apps.any.collection<AppInfo>('infos')`
    matches `apps/<anyId>/infos`. Paths are matched generically, so one
    declaration covers every parent id.
* Optional presentation tweaks:
  * `documentViewAddTypeNames({MyDoc: 'MyDoc'})` (or
    `documentViewAddTypeName(MyDoc, 'MyDoc')`) for the type labels shown next
    to fields.
  * `documentViewReferenceMap[MyDoc] = [FieldReference(['name'])]` adds field
    values under each item of the document list screen; `FieldReference` takes
    the path of the field inside the model (a list of keys/indexes).
* Navigate with the `goTo*` helpers, which push a `MaterialPageRoute` and
  initialize the explorer for you:
  * `goToFsDocumentRootScreen(context, firestore:)` — the root of the database,
  * `goToFsDocumentListScreen(context, firestore:, query:)` — a
    `CvQueryReference` (`myCollection.query().limit(20)`),
  * `goToFsDocumentViewScreen(context, firestore:, doc:)` — one document,
  * `goToFsDocumentEditScreen(context, firestore:, doc:)` — edit one document.
  The matching widgets (`FsDocumentRootScreen(firestore:)`,
  `FsDocumentListScreen(firestore:, query:)`, `FsDocumentViewScreen(firestore:,
  doc:)`, `FsDocumentEditScreen(firestore:, doc:)`) can be used directly in a
  route table instead.
* Embed a single document instead of a whole screen with
  `FsDocumentView(controller: FsDocumentViewController(firestore:, docRef:))`
  or `FsDocumentEdit(controller: FsDocumentEditController(firestore:,
  docRef:))`. Those controllers are typed on the document
  (`FsDocumentViewController<MyDoc>`), expose `stream` (live document),
  `docRef`, `delete()` and must be `close()`d in `dispose()`.
  `FsDocumentEditController` adds `editedDocument` and `futureEditedDocument`
  (the in-progress copy) plus `fieldsEditViews(doc)`.
* Keep the explorer behind a debug/admin gate: it exposes every field of every
  document and lets the user edit and delete them, and the screens are
  deliberately plain (no design, experimental API that can change).
* Anti-patterns: calling the widgets without registering the cv constructors
  (everything shows up as an untyped map document), declaring a concrete
  sub-collection path with a hard coded parent id instead of `any`, and
  forgetting to `close()` a controller created by hand.
* Testing: use an in memory firestore, `newFirestoreMemory()` from
  `package:tekartik_firebase_firestore_sembast/firestore_sembast.dart` (a dev
  dependency here), and drive `FsDocumentViewController` directly — the mapping
  helpers are plain global state, so call `documentViewAddCollections` in
  `setUp`.

## Examples

Startup: register the models, declare the schema, open the explorer from a
debug menu.

```dart
import 'package:flutter/material.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

class App extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');

  @override
  CvFields get fields => [name];
}

class AppInfo extends CvFirestoreDocumentBase {
  final value = CvField<int>('value');

  @override
  CvFields get fields => [value];
}

final appCollection = CvCollectionReference<App>('apps');

/// `apps/<anyAppId>/infos`
final appInfoCollection = appCollection.any.collection<AppInfo>('infos');

void initFirestoreExplorer() {
  cvAddConstructors([App.new, AppInfo.new]);
  documentViewAddCollections([appCollection, appInfoCollection]);
  documentViewAddTypeNames({App: 'App', AppInfo: 'AppInfo'});
}

class DebugMenu extends StatelessWidget {
  final Firestore firestore;

  const DebugMenu({super.key, required this.firestore});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Explore firestore'),
      onTap: () async {
        await goToFsDocumentRootScreen(context, firestore: firestore);
      },
    );
  }
}
```

A filtered list screen, with the `name` field shown under each item, and a
direct jump to one document or to its edit screen.

```dart
import 'package:flutter/material.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

class App extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');

  @override
  CvFields get fields => [name];
}

final appCollection = CvCollectionReference<App>('apps');

Future<void> showApps(BuildContext context, Firestore firestore) async {
  documentViewReferenceMap[App] = [FieldReference(['name'])];
  await goToFsDocumentListScreen(
    context,
    firestore: firestore,
    query: appCollection.query().orderBy('name').limit(20),
  );
}

Future<void> showApp(
  BuildContext context,
  Firestore firestore,
  String appId,
) async {
  var doc = appCollection.doc(appId);
  await goToFsDocumentViewScreen(context, firestore: firestore, doc: doc);
  if (context.mounted) {
    await goToFsDocumentEditScreen(context, firestore: firestore, doc: doc);
  }
}
```

Embedding one document inside an existing screen, with an explicit controller.

```dart
import 'package:flutter/material.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';

class App extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');

  @override
  CvFields get fields => [name];
}

class AppDebugView extends StatefulWidget {
  final Firestore firestore;
  final CvDocumentReference<App> docRef;

  const AppDebugView({
    super.key,
    required this.firestore,
    required this.docRef,
  });

  @override
  State<AppDebugView> createState() => _AppDebugViewState();
}

class _AppDebugViewState extends State<AppDebugView> {
  late final FsDocumentViewController<App> controller =
      FsDocumentViewController<App>(
        firestore: widget.firestore,
        docRef: widget.docRef,
      );

  @override
  void dispose() {
    controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FsDocumentView(controller: controller);
}
```

A test, against an in memory firestore.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

class App extends CvFirestoreDocumentBase {
  final name = CvField<String>('name');

  @override
  CvFields get fields => [name];
}

void main() {
  cvAddConstructors([App.new]);
  late Firestore firestore;
  setUp(() {
    firestore = newFirestoreMemory();
  });
  test('view controller', () async {
    var docRef = CvCollectionReference<App>('apps').doc('1');
    await docRef.set(firestore, App()..name.v = 'My app');

    var controller = FsDocumentViewController<App>(
      firestore: firestore,
      docRef: docRef,
    );
    var doc = await controller.stream.first;
    expect(doc.exists, isTrue);
    expect(doc.name.v, 'My app');
    controller.close();
  });
}
```
