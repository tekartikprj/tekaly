## 0.2.0

* `TekalyFilePicker.saveFile()`: save bytes to a file chosen by the user, with
  `tekalyDefaultMimeType` as the default mime type. Implementations must
  implement it.
* `TekalyFilePickerMemory` records them in `saveRequests` and returns
  `saveUri`, built from `directoryPath` by default.
* `tekalyFilePickerOrNull`, the global picker or `null` when not initialized.

## 0.1.0

* Initial version.
* `TekalyFilePicker` interface: `pickFile()`, `pickFiles()`,
  `pickDirectoryPath()` and the `pickImageFile()`/`pickAnyFile()`/
  `pickCustomFile()` shortcuts.
* `TekalyPickedFile`: `name`, `extension`, `uri`, `path`, `length()`,
  `readAsBytes()`, `readAsByteStream()`, `readAsString()`.
* `TekalyFilePickerMemory`/`TekalyPickedFileMemory` in memory implementation,
  with type filtering, `cancelled` and recorded `requests`.
* Global `tekalyFilePicker`.
