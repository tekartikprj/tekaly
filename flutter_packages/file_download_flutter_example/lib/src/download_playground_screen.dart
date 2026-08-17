import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tekaly_file_download/download_file.dart';
import 'package:tekaly_file_download/download_image.dart';
import 'package:tekaly_file_picker/file_picker.dart';

import 'download_log.dart';
import 'sample_content.dart';

/// The delay of the lazy generation.
const lazyDelay = Duration(seconds: 1);

/// Playground of the `tekaly_file_download` API.
class DownloadPlaygroundScreen extends StatefulWidget {
  /// Playground of the `tekaly_file_download` API.
  const DownloadPlaygroundScreen({super.key});

  @override
  State<DownloadPlaygroundScreen> createState() =>
      _DownloadPlaygroundScreenState();
}

class _DownloadPlaygroundScreenState extends State<DownloadPlaygroundScreen> {
  var _sample = downloadSamples.first;

  late final _filenameController = TextEditingController(
    text: _sample.filename,
  );
  late final _mimeTypeController = TextEditingController(
    text: _sample.mimeType ?? '',
  );
  final _sizeKbController = TextEditingController(text: '256');

  final _entries = <DownloadLogEntry>[];
  var _running = false;

  /// The content the sample last generated, kept for the preview.
  Uint8List? _bytes;

  String get _filename {
    var filename = _filenameController.text.trim();
    return filename.isEmpty ? _sample.filename : filename;
  }

  /// The explicit mime type, `null` when deduced from the filename.
  String? get _mimeType {
    var mimeType = _mimeTypeController.text.trim();
    return mimeType.isEmpty ? null : mimeType;
  }

  /// What `DownloadFileInfo` will use.
  String get _effectiveMimeType => _mimeType ?? filenameMimeType(_filename);

  int get _sizeKb => int.tryParse(_sizeKbController.text.trim()) ?? 256;

  @override
  void dispose() {
    _filenameController.dispose();
    _mimeTypeController.dispose();
    _sizeKbController.dispose();
    super.dispose();
  }

  void _selectSample(DownloadSample sample) {
    setState(() {
      _sample = sample;
      _filenameController.text = sample.filename;
      _mimeTypeController.text = sample.mimeType ?? '';
      _bytes = null;
    });
  }

  void _log(String action, String message, {bool failed = false}) {
    setState(() {
      _entries.add(
        DownloadLogEntry(action: action, message: message, failed: failed),
      );
    });
  }

  /// Generates the content, after [lazyDelay] when [lazy].
  ///
  /// The lazy case is what an app doing some real work (reading a file, calling
  /// an api, encoding an image) before downloading looks like.
  Future<Uint8List> _buildBytes({required bool lazy}) async {
    if (lazy) {
      await Future<void>.delayed(lazyDelay);
    }
    return _sample.build(_sizeKb);
  }

  Future<void> _download({required bool lazy, required bool asImage}) async {
    var action =
        '${asImage ? 'downloadImage' : 'downloadFile'}'
        '${lazy ? ' (lazy)' : ''}';
    setState(() => _running = true);
    var stopwatch = Stopwatch()..start();
    try {
      var bytes = await _buildBytes(lazy: lazy);
      var generatedMs = stopwatch.elapsedMilliseconds;
      var filename = _filename;
      String mimeType;
      if (asImage) {
        var imageInfo = DownloadImageInfo(filename: filename, data: bytes);
        mimeType = imageInfo.mimeType;
        await downloadImage(imageInfo);
      } else {
        var fileInfo = DownloadFileInfo(
          filename: filename,
          data: bytes,
          mimeType: _mimeType,
        );
        mimeType = fileInfo.mimeType;
        await downloadFile(fileInfo);
      }
      if (!mounted) {
        return;
      }
      setState(() => _bytes = bytes);
      _log(
        action,
        '$filename, ${bytes.length} bytes, $mimeType, '
        'generated in ${generatedMs}ms, '
        'returned in ${stopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      if (mounted) {
        _log(action, '$e', failed: true);
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Widget _card({required String title, String? subtitle, Widget? child}) =>
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle),
            ),
            if (child != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: child,
              ),
          ],
        ),
      );

  Widget _contentCard() => _card(
    title: '1. The content',
    subtitle: 'Every type, from the most usual to the most annoying one',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: downloadSamples
              .map(
                (sample) => ChoiceChip(
                  label: Text(sample.label),
                  selected: sample == _sample,
                  onSelected: (_) => _selectSample(sample),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _filenameController,
          decoration: const InputDecoration(
            labelText: 'filename',
            helperText: 'The extension drives the mime type',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mimeTypeController,
          decoration: const InputDecoration(
            labelText: 'mimeType (optional)',
            hintText: 'deduced from the filename when empty',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_sample.sized) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _sizeKbController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'size (kB)'),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 16),
        Text('DownloadFileInfo.mimeType: $_effectiveMimeType'),
        if (_sample.isImage && _bytes != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Image.memory(
              _bytes!,
              width: 64,
              filterQuality: FilterQuality.none,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _downloadCard() => _card(
    title: '2. The download',
    subtitle:
        'The lazy buttons generate the content 1s after the tap, which is '
        'where the web gets interesting',
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _running
              ? null
              : () => _download(lazy: false, asImage: false),
          icon: const Icon(Icons.download),
          label: const Text('downloadFile'),
        ),
        FilledButton.tonalIcon(
          onPressed: _running
              ? null
              : () => _download(lazy: true, asImage: false),
          icon: const Icon(Icons.hourglass_bottom),
          label: const Text('downloadFile after 1s'),
        ),
        OutlinedButton.icon(
          onPressed: _running
              ? null
              : () => _download(lazy: false, asImage: true),
          icon: const Icon(Icons.image),
          label: const Text('downloadImage'),
        ),
        OutlinedButton.icon(
          onPressed: _running
              ? null
              : () => _download(lazy: true, asImage: true),
          icon: const Icon(Icons.hourglass_bottom),
          label: const Text('downloadImage after 1s'),
        ),
      ],
    ),
  );

  Widget _behaviourCard() {
    var filePicker = tekalyFilePickerOrNull;
    return _card(
      title: '3. What happens',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            kIsWeb
                ? 'Web: tekaly_file_download_web clicks a synthetic anchor on a '
                      'blob url, the browser downloads it (or displays it, pdf '
                      'and images in particular).\n\n'
                      'A download triggered long after the user gesture can be '
                      'blocked (Safari especially): compare the immediate and '
                      'the lazy buttons, and generate the content before the '
                      'tap when it matters.'
                : 'Native: tekaly_file_picker_flutter opens a save dialog '
                      '(file_picker, or file_selector on linux desktop). The '
                      'delay does not matter here, cancelling the dialog is '
                      'not an error.',
          ),
          const SizedBox(height: 8),
          const Text('kIsWeb: $kIsWeb'),
          Text('tekalyFilePicker: ${filePicker ?? 'not initialized'}'),
        ],
      ),
    );
  }

  Widget _logCard() => Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: const Text('Log'),
          trailing: TextButton(
            onPressed: _entries.isEmpty ? null : () => setState(_entries.clear),
            child: const Text('Clear'),
          ),
        ),
        DownloadLogView(entries: _entries),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('tekaly_file_download playground'),
      bottom: _running
          ? const PreferredSize(
              preferredSize: Size.fromHeight(4),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [_contentCard(), _downloadCard(), _behaviourCard(), _logCard()],
    ),
  );
}
