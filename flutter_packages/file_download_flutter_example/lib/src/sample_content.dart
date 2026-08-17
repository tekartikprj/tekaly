import 'dart:convert';
import 'dart:typed_data';

/// A content the playground can download.
class DownloadSample {
  /// Short label, shown in the UI.
  final String label;

  /// Default filename, extension included.
  final String filename;

  /// Explicit mime type, `null` to let `filenameMimeType` deduce it from the
  /// filename.
  final String? mimeType;

  /// True when the content is a png or a jpeg, `downloadImage` can be used.
  final bool isImage;

  /// True when the content size is driven by the playground size field.
  final bool sized;

  /// Builds the content, `sizeKb` is only used when [sized] is true.
  final Uint8List Function(int sizeKb) build;

  /// A playground content.
  const DownloadSample({
    required this.label,
    required this.filename,
    required this.build,
    this.mimeType,
    this.isImage = false,
    this.sized = false,
  });

  @override
  String toString() => 'DownloadSample($label, $filename)';
}

/// A 16x16 checkerboard png.
final samplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAMElEQVR4nGP8HxDAAAOab1Lg'
  '7Osic7CKMzGQCGivgYUYdyOLD0I/MI7GAy2cRLIGALoEGFO75XD8AAAAAElFTkSuQmCC',
);

/// The same 16x16 checkerboard, as a jpeg.
final sampleJpgBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAoHBwgHBgoICAgLCgoLDhgQDg0NDh0VFhEYIx8l'
  'JCIfIiEmKzcvJik0KSEiMEExNDk7Pj4+JS5ESUM8SDc9Pjv/2wBDAQoLCw4NDhwQEBw7KCIo'
  'Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozv/wAAR'
  'CAAQABADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAA'
  'AgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkK'
  'FhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWG'
  'h4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl'
  '5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREA'
  'AgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYk'
  'NOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOE'
  'hYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk'
  '5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDJ/wCQ9/0w8j/gW7P5elH/ACHv+mHkf8C3'
  'Z/L0o/5D3/TDyP8AgW7P5elH/Ie/6YeR/wAC3Z/L0rt/h/3OT5+zv/6Vzf8Akp7f8X+/z/L2'
  'lv8A0jk/8mP/2Q==',
);

/// A one page pdf displaying [text], with a proper xref table so that any
/// viewer accepts it.
Uint8List pdfBytes(String text) {
  var content = 'BT /F1 24 Tf 40 100 Td ($text) Tj ET\n';
  var page =
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 200] '
      '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>';
  var objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    page,
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  var buffer = StringBuffer('%PDF-1.4\n');
  var offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  var xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (var offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );
  return utf8.encode(buffer.toString());
}

/// Roughly [sizeKb] kilobytes of text.
Uint8List textBytesOfSize(int sizeKb) {
  var buffer = StringBuffer();
  var line = 0;
  while (buffer.length < sizeKb * 1024) {
    buffer.writeln(
      '${(++line).toString().padLeft(6)}: '
      'The quick brown fox jumps over the lazy dog.',
    );
  }
  return utf8.encode(buffer.toString());
}

/// Exactly [sizeKb] kilobytes of bytes.
Uint8List binaryBytesOfSize(int sizeKb) =>
    Uint8List.fromList(List.generate(sizeKb * 1024, (index) => index % 256));

/// Every content the playground can download, from the most usual to the most
/// annoying one (no extension, big content, ...).
final downloadSamples = <DownloadSample>[
  DownloadSample(
    label: 'Text',
    filename: 'hello.txt',
    build: (_) => utf8.encode('Hello World from tekaly_file_download.\n'),
  ),
  DownloadSample(
    label: 'Json',
    filename: 'data.json',
    build: (_) => utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'hello': 'world',
        'list': [1, 2, 3],
      }),
    ),
  ),
  DownloadSample(
    label: 'Csv',

    /// `.csv` is not in the mime type map, hence the explicit mime type
    filename: 'data.csv',
    mimeType: 'text/csv',
    build: (_) => utf8.encode('name,value\nhello,1\nworld,2\n'),
  ),
  DownloadSample(
    label: 'Markdown',

    /// `.md` is not in the mime type map, `application/octet-stream` is used
    filename: 'notes.md',
    build: (_) => utf8.encode('# Hello\n\nFrom `tekaly_file_download`.\n'),
  ),
  DownloadSample(
    label: 'Html',
    filename: 'page.html',
    build: (_) => utf8.encode('<html><body><h1>Hello</h1></body></html>\n'),
  ),
  DownloadSample(
    label: 'Yaml',
    filename: 'config.yaml',
    build: (_) => utf8.encode('hello: world\nlist:\n  - 1\n  - 2\n'),
  ),
  DownloadSample(
    label: 'Calendar',
    filename: 'event.ics',
    build: (_) => utf8.encode(
      'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//tekaly//download//EN\r\n'
      'BEGIN:VEVENT\r\nUID:1@tekaly\r\nDTSTAMP:20260101T100000Z\r\n'
      'DTSTART:20260101T100000Z\r\nSUMMARY:Hello\r\nEND:VEVENT\r\n'
      'END:VCALENDAR\r\n',
    ),
  ),
  DownloadSample(
    label: 'Pdf',

    /// The browser might display it instead of downloading it
    filename: 'hello.pdf',
    build: (_) => pdfBytes('Hello tekaly'),
  ),
  DownloadSample(
    label: 'Png',
    filename: 'checker.png',
    isImage: true,
    build: (_) => samplePngBytes,
  ),
  DownloadSample(
    label: 'Jpeg',
    filename: 'checker.jpg',
    isImage: true,
    build: (_) => sampleJpgBytes,
  ),
  DownloadSample(
    label: 'Svg',

    /// An image, but not one `DownloadImageInfo` knows about (png or jpeg)
    filename: 'icon.svg',
    build: (_) => utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">'
      '<rect width="16" height="16" fill="#f55"/></svg>\n',
    ),
  ),
  DownloadSample(
    label: 'No extension',

    /// No extension at all, `application/octet-stream` is used
    filename: 'noextension',
    build: (_) => utf8.encode('Hello World\n'),
  ),
  const DownloadSample(
    label: 'Big text',
    filename: 'big.txt',
    sized: true,
    build: textBytesOfSize,
  ),
  const DownloadSample(
    label: 'Binary',
    filename: 'data.bin',
    sized: true,
    build: binaryBytesOfSize,
  ),
];
