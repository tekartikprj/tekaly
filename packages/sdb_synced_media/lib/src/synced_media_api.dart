import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cv/cv.dart';
import 'package:path/path.dart';
import 'package:tekartik_app_media/mime_type.dart';

import 'synced_media_file.dart';
import 'synced_media_source.dart';

/// Media api commands and models, transport agnostic: a request and a
/// response are json maps, sent by a [SyncedMediaApiClient] (secured api,
/// functions callable, http, rpc, in process) and handled on the server by a
/// [SyncedMediaApiService].
///
/// Contents travel base64 encoded in json, keep them small (server limits,
/// for example 10MB for a callable function) or read them through
/// [SyncedMediaSource.getMediaUrl].
abstract final class SyncedMediaApi {
  /// Add a content: [SyncedMediaApiAddRequest], empty response.
  static const commandAdd = 'syncedMediaAdd';

  /// Read a content: [SyncedMediaApiRefRequest], [SyncedMediaApiReadResponse].
  static const commandRead = 'syncedMediaRead';

  /// Delete a content: [SyncedMediaApiRefRequest], empty response.
  static const commandDelete = 'syncedMediaDelete';

  /// Network url of a content: [SyncedMediaApiRefRequest],
  /// [SyncedMediaApiUrlResponse].
  static const commandUrl = 'syncedMediaUrl';

  /// All commands.
  static const commands = [commandAdd, commandRead, commandDelete, commandUrl];
}

/// Request on a content.
class SyncedMediaApiRefRequest extends CvModelBase {
  /// Relative path of the content.
  final path = CvField<String>('path');

  @override
  CvFields get fields => [path];
}

/// Add request.
class SyncedMediaApiAddRequest extends SyncedMediaApiRefRequest {
  /// Media id.
  final uid = CvField<String>('uid');

  /// Mime type.
  final type = CvField<String>('type');

  /// Original filename.
  final filename = CvField<String>('filename');

  /// Base64 content.
  final data = CvField<String>('data');

  @override
  CvFields get fields => [...super.fields, uid, type, filename, data];
}

/// Read response.
class SyncedMediaApiReadResponse extends CvModelBase {
  /// Base64 content.
  final data = CvField<String>('data');

  @override
  CvFields get fields => [data];
}

/// Url response.
class SyncedMediaApiUrlResponse extends CvModelBase {
  /// Network url, null if none.
  final url = CvField<String>('url');

  @override
  CvFields get fields => [url];
}

/// Sends a media api command, implemented over a transport (secured api,
/// functions callable, http, rpc) or in process
/// ([SyncedMediaApiClientLocal]).
///
/// Errors (denied access, content not found) are thrown.
abstract interface class SyncedMediaApiClient {
  /// Sends [command] with [request], returns the response.
  Future<Map<String, Object?>> send(
    String command,
    Map<String, Object?> request,
  );
}

/// Exception of a media api request (invalid request, denied access).
class SyncedMediaApiException implements Exception {
  /// Message
  final String message;

  /// Media api exception.
  SyncedMediaApiException(this.message);

  @override
  String toString() => 'SyncedMediaApiException: $message';
}

/// Server side access check of [command] on [ref], throws to deny.
typedef SyncedMediaApiAccessCheck =
    FutureOr<void> Function(String command, SyncedMediaFileRef ref);

/// Server side handler of the media api, on top of a [source] (typically a
/// `SyncedMediaSourceStorage` with server credentials, the clients having no
/// direct access to the bucket).
class SyncedMediaApiService {
  /// Backing source.
  final SyncedMediaSource source;

  /// Optional access check (user rights, path prefix), throws to deny.
  final SyncedMediaApiAccessCheck? accessCheck;

  /// Maximum size of an added content, no limit if null.
  final int? maxSize;

  /// Media api server on [source].
  SyncedMediaApiService({required this.source, this.accessCheck, this.maxSize});

  /// True if [command] is a media api command.
  bool handles(String command) => SyncedMediaApi.commands.contains(command);

  Future<SyncedMediaFileRef> _ref(String command, String? path) async {
    if (path == null || !syncedMediaIsValidPath(path)) {
      throw SyncedMediaApiException('Invalid path $path');
    }
    var ref = SyncedMediaFileRef.fromPath(path);
    await accessCheck?.call(command, ref);
    return ref;
  }

  /// Handles [command] with [request], returns the response.
  Future<Map<String, Object?>> handle(
    String command,
    Map<String, Object?> request,
  ) async {
    switch (command) {
      case SyncedMediaApi.commandAdd:
        var add = SyncedMediaApiAddRequest()..fromMap(request);
        var ref = await _ref(command, add.path.v);
        var data = add.data.v;
        if (data == null) {
          throw SyncedMediaApiException('Missing data');
        }
        var bytes = base64Decode(data);
        var maxSize = this.maxSize;
        if (maxSize != null && bytes.length > maxSize) {
          throw SyncedMediaApiException('Size ${bytes.length} above $maxSize');
        }
        var filename = add.filename.v ?? url.basename(ref.path);
        await source.addMediaFile(
          file: SyncedMediaFile(
            uid: add.uid.v ?? url.basename(ref.path),
            originalFilename: filename,
            type: add.type.v ?? filenameMimeType(filename),
            path: ref.path,
            size: bytes.length,
          ),
          bytes: bytes,
        );
        return <String, Object?>{};
      case SyncedMediaApi.commandRead:
        var ref = await _ref(
          command,
          (SyncedMediaApiRefRequest()..fromMap(request)).path.v,
        );
        var bytes = await source.readMediaFileBytes(ref);
        return (SyncedMediaApiReadResponse()..data.v = base64Encode(bytes))
            .toMap();
      case SyncedMediaApi.commandDelete:
        var ref = await _ref(
          command,
          (SyncedMediaApiRefRequest()..fromMap(request)).path.v,
        );
        await source.deleteMediaFile(ref);
        return <String, Object?>{};
      case SyncedMediaApi.commandUrl:
        var ref = await _ref(
          command,
          (SyncedMediaApiRefRequest()..fromMap(request)).path.v,
        );
        var uri = await source.getMediaUrl(ref);
        return (SyncedMediaApiUrlResponse()..url.setValue(uri?.toString()))
            .toMap();
    }
    throw SyncedMediaApiException('Unsupported command $command');
  }
}

/// In process client calling a [service] directly (tests, in memory, or a
/// server using its own api), requests and responses go through a json round
/// trip like on the wire.
class SyncedMediaApiClientLocal implements SyncedMediaApiClient {
  /// Service called.
  final SyncedMediaApiService service;

  /// In process client of [service].
  SyncedMediaApiClientLocal({required this.service});

  Map<String, Object?> _wire(Map<String, Object?> map) =>
      (jsonDecode(jsonEncode(map)) as Map).cast<String, Object?>();

  @override
  Future<Map<String, Object?>> send(
    String command,
    Map<String, Object?> request,
  ) async {
    return _wire(await service.handle(command, _wire(request)));
  }
}

/// Media source going through the media api ([client]), the server holding
/// the actual source.
class SyncedMediaSourceApi implements SyncedMediaSource {
  /// Api client.
  final SyncedMediaApiClient client;

  /// Media source through [client].
  SyncedMediaSourceApi({required this.client});

  Map<String, Object?> _refRequest(SyncedMediaFileRef ref) =>
      (SyncedMediaApiRefRequest()..path.v = ref.path).toMap();

  @override
  Future<void> addMediaFile({
    required SyncedMediaFile file,
    required Uint8List bytes,
  }) async {
    await client.send(
      SyncedMediaApi.commandAdd,
      (SyncedMediaApiAddRequest()
            ..path.v = file.path
            ..uid.v = file.uid
            ..type.v = file.type
            ..filename.v = file.originalFilename
            ..data.v = base64Encode(bytes))
          .toMap(),
    );
  }

  @override
  Future<void> deleteMediaFile(SyncedMediaFileRef ref) async {
    await client.send(SyncedMediaApi.commandDelete, _refRequest(ref));
  }

  @override
  Future<Uri?> getMediaUrl(SyncedMediaFileRef ref) async {
    var response = SyncedMediaApiUrlResponse()
      ..fromMap(await client.send(SyncedMediaApi.commandUrl, _refRequest(ref)));
    var url = response.url.v;
    return url == null ? null : Uri.parse(url);
  }

  @override
  Future<Uint8List> readMediaFileBytes(SyncedMediaFileRef ref) async {
    var response = SyncedMediaApiReadResponse()
      ..fromMap(
        await client.send(SyncedMediaApi.commandRead, _refRequest(ref)),
      );
    var data = response.data.v;
    if (data == null) {
      throw SyncedMediaApiException('Missing data for $ref');
    }
    return base64Decode(data);
  }

  @override
  String toString() => 'SyncedMediaSourceApi($client)';
}
