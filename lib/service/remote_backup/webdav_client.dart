// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// Project imports:
import 'package:turna/service/remote_backup/remote_backup_config.dart';

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'WebDavException: $message'
      : 'WebDavException: $message (HTTP $statusCode)';
}

/// Server rejected username / password (or the account has no DAV access).
class WebDavAuthException extends WebDavException {
  const WebDavAuthException() : super('服务器拒绝了用户名或密码', statusCode: 401);
}

class WebDavNotFoundException extends WebDavException {
  WebDavNotFoundException(String path) : super('远端不存在: $path', statusCode: 404);
}

class WebDavProbeResult {
  const WebDavProbeResult(
      {required this.serverHeader, required this.davHeader});

  final String? serverHeader;
  final String? davHeader;
}

/// Thin WebDAV verb wrapper over `package:http` — enough for the remote
/// backup layout (PUT / GET / HEAD / MKCOL / DELETE / MOVE / OPTIONS), no
/// extra dependencies and no platform channels, so it works wherever the
/// http package does.
///
/// Redirects are not followed (credentials must not leak to another host).
/// Ask users to enter the final `https://` URL directly.
class WebDavClient {
  WebDavClient({
    required Uri baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _base = _normalizeBase(baseUrl);

  WebDavClient.fromConfig(RemoteBackupResolvedConfig config,
      {http.Client? client})
      : this(
          baseUrl: Uri.parse(config.normalized().serverUrl),
          username: config.username.trim(),
          password: config.password,
          client: client,
        );

  final String username;
  final String password;
  final http.Client _client;
  final Uri _base;

  static const _shortOpTimeout = Duration(seconds: 30);

  static Uri _normalizeBase(Uri url) {
    var path = url.path.replaceAll(RegExp(r'/+$'), '');
    if (path.isEmpty) path = '';
    return url.replace(path: path);
  }

  Uri _uri(String remotePath) {
    final clean = remotePath.startsWith('/') ? remotePath : '/$remotePath';
    final encoded = clean.split('/').map(Uri.encodeComponent).join('/');
    return _base.replace(path: '${_base.path}$encoded');
  }

  String get _authValue =>
      'Basic ${base64.encode(utf8.encode('$username:$password'))}';

  void _authorize(http.BaseRequest request) {
    request.headers[HttpHeaders.authorizationHeader] = _authValue;
    request.followRedirects = false;
    request.persistentConnection = true;
  }

  Never _fail(int statusCode, String what) {
    if (statusCode == 401 || statusCode == 403) {
      throw const WebDavAuthException();
    }
    if (statusCode == 404) {
      throw WebDavNotFoundException(what);
    }
    throw WebDavException('$what 失败', statusCode: statusCode);
  }

  Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } catch (_) {
      // Body draining is best-effort keep-alive hygiene.
    }
  }

  void close() => _client.close();

  /// OPTIONS the server root — verifies reachability, credentials and that
  /// the endpoint actually speaks WebDAV.
  Future<WebDavProbeResult> probe() async {
    final request = http.Request('OPTIONS', _uri('/'));
    _authorize(request);
    final response = await _client.send(request).timeout(_shortOpTimeout);
    await _drain(response);
    final code = response.statusCode;
    if (code == 401 || code == 403) throw const WebDavAuthException();
    if (code < 200 || code >= 300) {
      throw WebDavException('服务器不可用或地址不正确', statusCode: code);
    }
    return WebDavProbeResult(
      serverHeader: response.headers['server'],
      davHeader: response.headers['dav'],
    );
  }

  Future<bool> exists(String path) async {
    final request = http.Request('HEAD', _uri(path));
    _authorize(request);
    final response = await _client.send(request).timeout(_shortOpTimeout);
    await _drain(response);
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404) return false;
    _fail(response.statusCode, '检查 $path');
  }

  /// Creates every missing path segment. Tolerates collections that already
  /// exist (405) — the common case after the first backup.
  Future<void> mkcolRecursive(String path) async {
    final segments =
        path.split('/').where((segment) => segment.isNotEmpty).toList();
    var built = '';
    for (final segment in segments) {
      built = '$built/$segment';
      if (await exists(built)) continue;
      final request = http.Request('MKCOL', _uri(built));
      _authorize(request);
      final response = await _client.send(request).timeout(_shortOpTimeout);
      await _drain(response);
      final code = response.statusCode;
      if (code == 201 || code == 200) continue;
      // 405 = already exists (some servers answer it instead of for HEAD).
      if (code == 405) continue;
      _fail(code, '创建目录 $built');
    }
  }

  /// Streams [file] to [path] without buffering it in memory; [onProgress]
  /// reports cumulative sent bytes. No total timeout — media uploads may be
  /// large and slow, transport-level failures still throw.
  Future<void> putFile(
    String path,
    File file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();
    final uri = _uri(path);
    final request = http.StreamedRequest('PUT', uri);
    _authorize(request);
    request.contentLength = length;
    var sent = 0;
    file.openRead().listen(
      (chunk) {
        sent += chunk.length;
        onProgress?.call(sent, length);
        request.sink.add(chunk);
      },
      onDone: request.sink.close,
      onError: (Object error, StackTrace stackTrace) =>
          request.sink.addError(error, stackTrace),
      cancelOnError: true,
    );
    final response = await _client.send(request);
    await _drain(response);
    final code = response.statusCode;
    if (code < 200 || code >= 300) _fail(code, '上传 $path');
  }

  /// Small in-memory PUT (manifest json and friends) with atomic overwrite.
  Future<void> putBytes(String path, List<int> bytes) async {
    final request = http.Request('PUT', _uri(path));
    _authorize(request);
    request.bodyBytes = bytes;
    final response = await _client.send(request).timeout(_shortOpTimeout);
    await _drain(response);
    final code = response.statusCode;
    if (code < 200 || code >= 300) _fail(code, '上传 $path');
  }

  Future<Uint8List> getBytes(String path) async {
    final request = http.Request('GET', _uri(path));
    _authorize(request);
    final response = await _client.send(request).timeout(_shortOpTimeout);
    final code = response.statusCode;
    if (code < 200 || code >= 300) {
      await _drain(response);
      _fail(code, '下载 $path');
    }
    final collected = await http.Response.fromStream(response);
    return collected.bodyBytes;
  }

  /// Streams [path] to [dest] via a `.download` sibling + rename, so a
  /// partial download never occupies the target path.
  Future<void> getToFile(String path, File dest) async {
    final request = http.Request('GET', _uri(path));
    _authorize(request);
    final response = await _client.send(request);
    final code = response.statusCode;
    if (code < 200 || code >= 300) {
      await _drain(response);
      _fail(code, '下载 $path');
    }
    await dest.parent.create(recursive: true);
    final tmp = File('${dest.path}.download');
    final sink = tmp.openWrite();
    try {
      await response.stream.pipe(sink);
    } catch (_) {
      await sink.close().catchError((_) => sink);
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    if (response.contentLength != null &&
        await tmp.length() != response.contentLength) {
      await tmp.delete();
      throw WebDavException('下载不完整: $path', statusCode: code);
    }
    await tmp.rename(dest.path);
  }

  /// Deletes a file or collection; a missing target is a no-op.
  Future<void> delete(String path) async {
    final request = http.Request('DELETE', _uri(path));
    _authorize(request);
    final response = await _client.send(request).timeout(_shortOpTimeout);
    await _drain(response);
    final code = response.statusCode;
    if (code == 404 || code == 200 || code == 204) return;
    _fail(code, '删除 $path');
  }

  /// Server-side rename with overwrite — used to publish `manifest.json`
  /// atomically (PUT to `.tmp`, then MOVE on top).
  Future<void> move(String from, String to) async {
    final request = http.Request('MOVE', _uri(from));
    _authorize(request);
    request.headers['Destination'] = _uri(to).toString();
    request.headers['Overwrite'] = 'T';
    final response = await _client.send(request).timeout(_shortOpTimeout);
    await _drain(response);
    final code = response.statusCode;
    if (code == 201 || code == 204 || code == 200) return;
    _fail(code, '移动 $from → $to');
  }
}

/// Joins remote layout segments into a POSIX-style remote path.
String davPath(String a, [String? b, String? c]) =>
    p.posix.joinAll([a, if (b != null) b, if (c != null) c]).replaceAll(
        RegExp(r'^/+'), '/');
