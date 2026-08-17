import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

import 'picked_file_tile.dart';
import 'sample_files.dart';

/// Which implementation the playground currently drives.
enum FilePickerKind {
  /// The real one, `file_picker` (or `file_selector` on linux).
  flutter,

  /// The in memory one, what tests use.
  memory,
}

/// Playground of the `TekalyFilePicker` API.
class PlaygroundScreen extends StatefulWidget {
  /// Playground of the `TekalyFilePicker` API.
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> {
  /// The real picker, created once so that `lastDirectory` is kept.
  final _flutterFilePicker = tekalyFilePickerFlutter;

  /// The mock picker, pre-filled with a few files.
  final _memoryFilePicker = newSampleMemoryFilePicker();

  var _kind = FilePickerKind.flutter;
  var _type = TekalyPickFileType.any;

  final _allowedExtensionsController = TextEditingController(text: 'json,txt');
  final _dialogTitleController = TextEditingController();
  final _initialDirectoryController = TextEditingController();

  var _files = <TekalyPickedFile>[];
  String? _directoryPath;
  String? _error;
  var _running = false;

  /// The very same interface, whatever the implementation is.
  TekalyFilePicker get _filePicker => switch (_kind) {
    FilePickerKind.flutter => _flutterFilePicker,
    FilePickerKind.memory => _memoryFilePicker,
  };

  List<String>? get _allowedExtensions {
    if (_type != TekalyPickFileType.custom) {
      return null;
    }
    return _allowedExtensionsController.text
        .split(',')
        .map((extension) => extension.trim())
        .where((extension) => extension.isNotEmpty)
        .toList();
  }

  String? _textOrNull(TextEditingController controller) {
    var text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  void dispose() {
    _allowedExtensionsController.dispose();
    _dialogTitleController.dispose();
    _initialDirectoryController.dispose();
    super.dispose();
  }

  /// Run [action], displaying whatever it throws (an `ArgumentError` when
  /// `custom` is used without extension for instance).
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<void> _pickFile() => _run(() async {
    var file = await _filePicker.pickFile(
      type: _type,
      allowedExtensions: _allowedExtensions,
      dialogTitle: _textOrNull(_dialogTitleController),
      initialDirectory: _textOrNull(_initialDirectoryController),
    );
    if (mounted) {
      setState(() => _files = [?file]);
    }
  });

  Future<void> _pickFiles() => _run(() async {
    var files = await _filePicker.pickFiles(
      type: _type,
      allowedExtensions: _allowedExtensions,
      dialogTitle: _textOrNull(_dialogTitleController),
      initialDirectory: _textOrNull(_initialDirectoryController),
    );
    if (mounted) {
      setState(() => _files = files);
    }
  });

  Future<void> _pickDirectoryPath() => _run(() async {
    var path = await _filePicker.pickDirectoryPath(
      dialogTitle: _textOrNull(_dialogTitleController),
      initialDirectory: _textOrNull(_initialDirectoryController),
    );
    if (mounted) {
      setState(() => _directoryPath = path);
    }
  });

  void _clear() {
    setState(() {
      _files = [];
      _directoryPath = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('tekaly_file_picker playground'),
      bottom: _running
          ? const PreferredSize(
              preferredSize: Size.fromHeight(4),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildImplementation(),
        const Divider(height: 32),
        _buildRequest(),
        const Divider(height: 32),
        _buildActions(),
        const Divider(height: 32),
        _buildResult(),
      ],
    ),
  );

  Widget _buildTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _buildImplementation() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildTitle('Implementation'),
      SegmentedButton<FilePickerKind>(
        segments: const [
          ButtonSegment(
            value: FilePickerKind.flutter,
            label: Text('Flutter'),
            icon: Icon(Icons.phone_android),
          ),
          ButtonSegment(
            value: FilePickerKind.memory,
            label: Text('Memory'),
            icon: Icon(Icons.memory),
          ),
        ],
        selected: {_kind},
        onSelectionChanged: (selection) {
          setState(() {
            _kind = selection.first;
            _files = [];
            _directoryPath = null;
            _error = null;
          });
        },
      ),
      const SizedBox(height: 8),
      Text(switch (_kind) {
        FilePickerKind.flutter =>
          'TekalyFilePickerFlutter: real dialogs. '
              'lastDirectory: ${_flutterFilePicker.lastDirectory ?? '<none>'}',
        FilePickerKind.memory =>
          'TekalyFilePickerMemory: no dialog, '
              '${_memoryFilePicker.files.length} file(s) in memory, '
              'filtered by the requested type. This is what tests use.',
      }, style: Theme.of(context).textTheme.bodySmall),
      if (_kind == FilePickerKind.memory) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Simulate a cancelled dialog'),
          subtitle: const Text('every pick returns null/empty'),
          value: _memoryFilePicker.cancelled,
          onChanged: (value) =>
              setState(() => _memoryFilePicker.cancelled = value),
        ),
      ],
    ],
  );

  Widget _buildRequest() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildTitle('Request'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var type in TekalyPickFileType.values)
            ChoiceChip(
              label: Text(type.name),
              selected: _type == type,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _type = type);
                }
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _allowedExtensionsController,
        enabled: _type == TekalyPickFileType.custom,
        decoration: const InputDecoration(
          labelText: 'allowedExtensions',
          helperText: 'comma separated, custom only, required then',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dialogTitleController,
        decoration: const InputDecoration(
          labelText: 'dialogTitle',
          helperText: 'optional, ignored on some platforms',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _initialDirectoryController,
        decoration: const InputDecoration(
          labelText: 'initialDirectory',
          helperText: 'optional, defaults to the last picked directory',
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );

  Widget _buildActions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FilledButton.icon(
        onPressed: _running ? null : _pickFile,
        icon: const Icon(Icons.insert_drive_file_outlined),
        label: const Text('pickFile'),
      ),
      FilledButton.icon(
        onPressed: _running ? null : _pickFiles,
        icon: const Icon(Icons.file_copy_outlined),
        label: const Text('pickFiles'),
      ),
      FilledButton.icon(
        onPressed: _running ? null : _pickDirectoryPath,
        icon: const Icon(Icons.folder_outlined),
        label: const Text('pickDirectoryPath'),
      ),
      OutlinedButton.icon(
        onPressed: _running ? null : _clear,
        icon: const Icon(Icons.clear),
        label: const Text('Clear'),
      ),
    ],
  );

  Widget _buildResult() {
    var error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle('Result'),
        if (error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        if (_directoryPath case var path?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder),
            title: const Text('pickDirectoryPath'),
            subtitle: Text(path),
          ),
        if (_files.isEmpty && error == null)
          Text(
            'Nothing picked yet. A cancelled dialog gives null for pickFile '
            'and an empty list for pickFiles.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (var file in _files) PickedFileTile(file: file),
        if (_kind == FilePickerKind.memory) ...[
          const Divider(height: 32),
          _buildTitle('Recorded requests'),
          Text(
            'The memory picker records every request, so a test can assert '
            'what the code under test asked for.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var request in _memoryFilePicker.requests.reversed.take(10))
            Text('• $request', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Format [bytes] as a human readable size.
String formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Read [file] chunk by chunk, returning the chunk count and the total size.
Future<(int, int)> readByteStreamInfo(TekalyPickedFile file) async {
  var chunkCount = 0;
  var size = 0;
  await for (var chunk in file.readAsByteStream()) {
    chunkCount++;
    size += chunk.length;
  }
  return (chunkCount, size);
}

/// Read [file] at once.
Future<Uint8List> readBytes(TekalyPickedFile file) => file.readAsBytes();
