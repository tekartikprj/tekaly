import 'package:flutter/material.dart';

/// One line of the playground log.
class DownloadLogEntry {
  /// When it happened.
  final DateTime time;

  /// What was called (`downloadFile`, `downloadImage (lazy)`, ...).
  final String action;

  /// What happened.
  final String message;

  /// True when [message] holds an error.
  final bool failed;

  /// A log line.
  DownloadLogEntry({
    required this.action,
    required this.message,
    this.failed = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  /// `hh:mm:ss.mmm`.
  String get timeText => time.toIso8601String().split('T').last;

  @override
  String toString() => '$timeText $action: $message';
}

/// The playground log, most recent first.
class DownloadLogView extends StatelessWidget {
  /// The entries, in order.
  final List<DownloadLogEntry> entries;

  /// The playground log.
  const DownloadLogView({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const ListTile(
        title: Text('Nothing downloaded yet'),
        subtitle: Text('Every call is logged here, with its duration'),
      );
    }
    var theme = Theme.of(context);
    return Column(
      children: entries.reversed
          .map(
            (entry) => ListTile(
              dense: true,
              leading: Icon(
                entry.failed ? Icons.error_outline : Icons.download_done,
                color: entry.failed ? theme.colorScheme.error : null,
              ),
              title: Text(entry.action),
              subtitle: Text(entry.message),
              trailing: Text(entry.timeText, style: theme.textTheme.bodySmall),
            ),
          )
          .toList(),
    );
  }
}
