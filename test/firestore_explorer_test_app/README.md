# tekaly_firestore_explorer_test_app

A Flutter app to try `tekaly_firestore_explorer` by hand: a local Firestore
(`firestore_sembast`) holding an `apps` collection, typed documents
(`lib/models.dart`) and the explorer screens (root, a collection list, a
document).

Run it from this folder, on a desktop or the web:

```sh
flutter run -d linux        # or macos, windows, chrome
flutter run -d linux -t lib/main_no_track_changes.dart
```

- `lib/main.dart`: the explorer with its live document updates.
- `lib/main_no_track_changes.dart`: the same without tracking changes
  (`forceNoTrackChanges`).

The data is kept in `.local/tk_firestore_explorer_test_app/` (relative to the
current folder) on desktop, in IndexedDB on the web; mobile is not set up
(the relative folder is not writable there).

A typed model holding nested models needs its builders registered
(`initFsBuilders()`), the type names shown by the explorer are optional
(`documentViewAddTypeNames`).

`flutter test` runs `test/models_test.dart` (every model can be read).
