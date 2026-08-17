import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tekaly_file_picker_flutter/file_picker_flutter.dart';

import 'playground_screen.dart';

/// Everything a [TekalyPickedFile] exposes, plus the 2 ways of reading it.
class PickedFileTile extends StatefulWidget {
  /// The picked file.
  final TekalyPickedFile file;

  /// Everything a [TekalyPickedFile] exposes.
  const PickedFileTile({super.key, required this.file});

  @override
  State<PickedFileTile> createState() => _PickedFileTileState();
}

class _PickedFileTileState extends State<PickedFileTile> {
  /// Content, only read on demand.
  Uint8List? _bytes;

  /// Chunk count and size of the last stream read.
  (int, int)? _streamInfo;

  String? _error;

  bool get _isImage =>
      tekalyImageFileExtensions.contains(widget.file.extension);

  Future<void> _readAsBytes() async {
    try {
      var bytes = await widget.file.readAsBytes();
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
  }

  Future<void> _readAsByteStream() async {
    try {
      var info = await readByteStreamInfo(widget.file);
      if (mounted) {
        setState(() {
          _streamInfo = info;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
  }

  Widget _buildField(String name, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$name: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value ?? 'null'),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    var file = widget.file;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _buildField('extension', file.extension),

            /// null on the web, and for a content uri on mobile
            _buildField('path', file.path),
            _buildField('uri', file.uri?.toString()),
            _buildField('runtimeType', '${file.runtimeType}'),
            FutureBuilder<int>(
              future: file.length(),
              builder: (context, snapshot) => _buildField(
                'length()',
                snapshot.hasError
                    ? '${snapshot.error}'
                    : (snapshot.data == null
                          ? '...'
                          : formatSize(snapshot.data!)),
              ),
            ),
            if (_bytes case var bytes?)
              _buildField('readAsBytes()', formatSize(bytes.length)),
            if (_streamInfo case var info?)
              _buildField(
                'readAsByteStream()',
                '${info.$1} chunk(s), ${formatSize(info.$2)}',
              ),
            if (_error case var error?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _readAsBytes,
                  child: const Text('readAsBytes'),
                ),
                OutlinedButton(
                  onPressed: _readAsByteStream,
                  child: const Text('readAsByteStream'),
                ),
              ],
            ),
            if (_isImage && _bytes != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Image.memory(
                    _bytes!,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (context, error, stackTrace) =>
                        Text('$error'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
