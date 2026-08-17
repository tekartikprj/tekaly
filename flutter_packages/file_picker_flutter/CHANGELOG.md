## 0.2.0

* `saveFile()`, on top of `FilePicker.saveFile` (`file_selector`
  `getSaveLocation` + a write on linux desktop). `lastDirectory` is remembered
  from the saved file too.

## 0.1.0

* Initial version.
* `TekalyFilePickerFlutter`, a `TekalyFilePicker` implementation on top of
  `file_picker` 12, with a `file_selector` (gtk) fallback on linux.
* `initTekalyFilePickerFlutter()` sets the global `tekalyFilePicker`.
* `lastDirectory` is remembered and reused as the next initial directory.
* `tekaly_file_picker` is re-exported, a single import is enough.
