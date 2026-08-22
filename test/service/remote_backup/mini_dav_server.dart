// Dart imports:
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal in-process WebDAV server for tests: OPTIONS / PUT / GET / HEAD /
/// MKCOL / DELETE / MOVE with optional Basic auth, backed by a temp
/// directory. Implements just enough DAV semantics (409 on missing parent,
/// 405 on existing collection, Overwrite header on MOVE) to exercise
/// [WebDavClient] against a real loopback HTTP stack.
class MiniDavServer {
  MiniDavServer({this.username, this.password})
      : root = Directory.systemTemp.createTempSync('turna_mini_dav');

  final String? username;
  final String? password;
  final Directory root;
  HttpServer? _server;

  Uri get baseUri {
    final server = _server;
    if (server == null) {
      throw StateError('MiniDavServer not started');
    }
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (Object _) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  /// Maps a decoded URL path to a filesystem path inside [root], rejecting
  /// traversal attempts.
  String? _fsPathFor(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s == '.')) return null;
    if (segments.isEmpty) return null;
    return '${root.path}/${segments.join('/')}';
  }

  FileSystemEntity? _entityFor(String path) {
    final fsPath = _fsPathFor(path);
    if (fsPath == null) return null;
    if (File(fsPath).existsSync()) return File(fsPath);
    if (Directory(fsPath).existsSync()) return Directory(fsPath);
    return null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_authorized(request)) {
        response.statusCode = HttpStatus.unauthorized;
        response.headers.set('WWW-Authenticate', 'Basic realm="mini-dav"');
        await response.close();
        return;
      }
      switch (request.method) {
        case 'OPTIONS':
          response.statusCode = HttpStatus.ok;
          response.headers.set('DAV', '1, 2');
          response.headers.set('Allow',
              'OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE');
          await response.close();
        case 'PUT':
          final fsPath = _fsPathFor(request.uri.path);
          if (fsPath == null ||
              !Directory(File(fsPath).parent.path).existsSync()) {
            response.statusCode = HttpStatus.conflict;
            await response.close();
            return;
          }
          final file = File(fsPath);
          final existed = file.existsSync();
          final body = await request.fold<BytesBuilder>(
              BytesBuilder(), (b, chunk) => b..add(chunk));
          await file.writeAsBytes(body.takeBytes(), flush: true);
          response.statusCode =
              existed ? HttpStatus.noContent : HttpStatus.created;
          await response.close();
        case 'GET':
          final entity = _entityFor(request.uri.path);
          if (entity is! File) {
            response.statusCode = HttpStatus.notFound;
            await response.close();
            return;
          }
          response.statusCode = HttpStatus.ok;
          response.contentLength = entity.lengthSync();
          await entity.openRead().pipe(response);
        case 'HEAD':
          final entity = _entityFor(request.uri.path);
          if (entity == null) {
            response.statusCode = HttpStatus.notFound;
            await response.close();
            return;
          }
          response.statusCode = HttpStatus.ok;
          response.contentLength = entity is File ? entity.lengthSync() : 0;
          await response.close();
        case 'MKCOL':
          final fsPath = _fsPathFor(request.uri.path);
          if (fsPath == null) {
            response.statusCode = HttpStatus.forbidden;
            await response.close();
            return;
          }
          if (File(fsPath).existsSync() || Directory(fsPath).existsSync()) {
            response.statusCode = HttpStatus.methodNotAllowed;
            await response.close();
            return;
          }
          if (!Directory(File(fsPath).parent.path).existsSync()) {
            response.statusCode = HttpStatus.conflict;
            await response.close();
            return;
          }
          Directory(fsPath).createSync();
          response.statusCode = HttpStatus.created;
          await response.close();
        case 'DELETE':
          final entity = _entityFor(request.uri.path);
          if (entity == null) {
            response.statusCode = HttpStatus.notFound;
            await response.close();
            return;
          }
          entity.deleteSync(recursive: true);
          response.statusCode = HttpStatus.noContent;
          await response.close();
        case 'MOVE':
          final source = _entityFor(request.uri.path);
          final destinationHeader = request.headers.value('Destination');
          final destinationFsPath = destinationHeader == null
              ? null
              : _fsPathFor(Uri.parse(destinationHeader).path);
          if (source == null || destinationFsPath == null) {
            response.statusCode = HttpStatus.badRequest;
            await response.close();
            return;
          }
          final overwrite = request.headers.value('Overwrite')?.toUpperCase();
          final destinationExists = File(destinationFsPath).existsSync() ||
              Directory(destinationFsPath).existsSync();
          if (destinationExists && overwrite != 'T') {
            response.statusCode = HttpStatus.preconditionFailed;
            await response.close();
            return;
          }
          Directory(File(destinationFsPath).parent.path)
              .createSync(recursive: true);
          source.renameSync(destinationFsPath);
          response.statusCode = HttpStatus.noContent;
          await response.close();
        default:
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {
        // Response already closed.
      }
    }
  }

  bool _authorized(HttpRequest request) {
    if (username == null) return true;
    final header = request.headers.value('Authorization');
    if (header == null || !header.startsWith('Basic ')) return false;
    final decoded =
        utf8.decode(base64.decode(header.substring('Basic '.length)));
    return decoded == '$username:$password';
  }
}
