# tekaly_firestore_explorer

An experimental Firestore explorer for Flutter debug and admin screens: it
lists, shows, edits, copies and deletes the documents of a
`tekartik_firebase_firestore` database, typed with `cv` models
(`CvFirestoreDocument`) when it knows them, as plain maps otherwise. A
developer tool, not an end user UI: keep it behind a debug or admin gate.

## Getting started

Not on pub.dev, add the git dependency:

```yaml
dependencies:
  tekaly_firestore_explorer:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: flutter_packages/firestore_explorer
```

Declare the models and where they live, then open a screen:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:tekaly_firestore_explorer/firestore_explorer.dart';
import 'package:tekartik_firebase_firestore_sembast/firestore_sembast.dart';

class Note extends CvFirestoreDocumentBase {
  final title = CvField<String>('title');
  final tags = CvListField<String>('tags');

  @override
  CvFields get fields => [title, tags];
}

final noteCollection = CvCollectionReference<Note>('notes');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cvAddConstructors([Note.new]);
  documentViewAddCollections([noteCollection]);
  documentViewAddTypeNames({Note: 'Note'});

  // Any Firestore of tekartik_firebase_firestore, in memory here.
  var firestore = newFirestoreMemory();
  await noteCollection.doc('n1').set(
    firestore,
    Note()
      ..title.v = 'Hello'
      ..tags.v = ['a', 'b'],
  );
  runApp(MaterialApp(home: FsDocumentRootScreen(firestore: firestore)));
}
```

The root screen lists the declared collections, a collection its documents
(the declared ones first), a document its fields and sub collections; the
edit screen writes the whole document back on save. Tapping a value copies
it to the clipboard. The `goToFs...Screen(context, firestore: ...)` helpers
push the same screens from an existing app.

Platforms: every Flutter platform the Firestore implementation supports.
`tekaly/test/firestore_explorer_test_app` in this repository is a runnable
app on a local sembast Firestore.

## Pitfalls

- Register the `cv` constructors before opening a screen: an unknown
  document shows up as a plain map (`CvFirestoreMapDocument`).
- A sub collection under any parent document is declared once with `any`:
  `noteCollection.any.collection<Comment>('comments')`.
- A `FsDocumentViewController` or `FsDocumentEditController` created by
  hand is closed by its owner (`close()` in `dispose()`).
- Saving replaces the whole document (`set`): fields unknown to the model
  are dropped.

Package skill (for AI coding agents, `skills/`):
`tekaly-firestore-explorer-browse-documents`.
