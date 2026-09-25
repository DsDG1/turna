import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:turna/application/anki_official/render/official_anki_http_range.dart';
import 'package:turna/application/anki_official/render/official_anki_media_path.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_mime.dart';
import 'package:turna/core/logger.dart';

typedef OfficialAnkiAssetLoader = Future<ByteData?> Function(String name);

/// iOS stand-in for the Android `https://anki.local` WebView interceptor.
///
/// WKWebView offers no `shouldInterceptRequest`, so the reviewer shell and
/// the collection media are served by an in-process loopback HTTP server
/// instead. The bundled reviewer assets still reference `https://anki.local`;
/// text assets are rewritten to this server's origin at serve time so the
/// shell, its CSP meta, and media URLs work unmodified. Response headers and
/// the classification policy mirror `OfficialAnkiMediaHandler.kt`.
class OfficialAnkiLocalServer {
  OfficialAnkiLocalServer._(
    this._server,
    this._mediaResolver,
    this._assetLoader,
  );

  final HttpServer _server;
  final OfficialAnkiMediaResolver _mediaResolver;
  final OfficialAnkiAssetLoader _assetLoader;

  static const _assetRoot = 'assets/anki_reviewer/';
  static const _textAssetExtensions = <String>{
    '.html',
    '.css',
    '.js',
    '.json',
    '.map',
    '.svg',
  };

  int get port => _server.port;

  String get origin => 'http://${InternetAddress.loopbackIPv4.address}:$port';

  String get shellUrl =>
      '$origin${OfficialAnkiMediaPath.assetPrefix}reviewer.html';

  bool isShellUrl(String url) =>
      url == shellUrl || url.startsWith('$shellUrl?');

  /// Same policy as `OfficialAnkiCsp.VALUE` on Android with the virtual
  /// origin replaced by this server's loopback origin.
  String get csp => "default-src 'none'; "
      "img-src $origin data: blob:; "
      "media-src $origin data: blob:; "
      "font-src $origin data:; "
      "style-src 'unsafe-inline' $origin; "
      "script-src 'unsafe-inline' $origin; "
      "connect-src 'none'; "
      "frame-src $origin; "
      "object-src 'none'; "
      "base-uri $origin${OfficialAnkiMediaPath.mediaPrefix}; "
      "form-action 'none';";

  static Future<OfficialAnkiLocalServer> start({
    required Directory mediaRoot,
    OfficialAnkiAssetLoader? assetLoader,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final self = OfficialAnkiLocalServer._(
      server,
      OfficialAnkiMediaResolver(mediaRoot),
      assetLoader ?? _defaultAssetLoader,
    );
    unawaited(() async {
      await for (final request in server) {
        unawaited(
          self._handle(request).catchError((Object error, StackTrace stack) {
            logger.w(
              '[OfficialAnkiLocalServer] request failed',
              error: error,
              stackTrace: stack,
            );
            try {
              request.response.close();
            } catch (_) {
              // Response may already be closed; nothing else to do.
            }
          }),
        );
      }
    }());
    return self;
  }

  static Future<ByteData?> _defaultAssetLoader(String name) =>
      rootBundle.load('$_assetRoot$name');

  Future<void> dispose() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    // `request.uri.path` preserves the wire encoding (same input the Android
    // interceptor sees via `uri.encodedPath`), so the shared classifier
    // applies unchanged: single-decode, traversal and origin rules included.
    final decision = _mediaResolver.resolveEncodedPath(request.uri.path);
    if (!decision.allowed) {
      return _deny(
        request.response,
        decision.reason == 'missing'
            ? HttpStatus.notFound
            : HttpStatus.forbidden,
        decision.reason ?? 'denied',
      );
    }
    if (decision.assetName != null) {
      return _serveAsset(request, decision.assetName!);
    }
    return _serveMedia(request, decision);
  }

  Future<void> _serveAsset(HttpRequest request, String name) async {
    final response = request.response;
    if (!OfficialAnkiMediaPath.isAllowedAsset(name)) {
      return _deny(response, HttpStatus.forbidden, 'asset_name');
    }
    final data = await _assetLoader(name);
    if (data == null) {
      return _deny(
        response,
        HttpStatus.notFound,
        name.contains('mathjax') || name.endsWith('tex-svg-full.js')
            ? 'MATHJAX_ASSET_MISSING'
            : 'asset_missing',
      );
    }
    var bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (_textAssetExtensions.any(name.endsWith)) {
      bytes = utf8.encode(
        utf8
            .decode(bytes, allowMalformed: true)
            .replaceAll('https://anki.local', origin),
      );
    }
    final mime = OfficialAnkiMime.mimeForName(name);
    _corsHeaders(response, mime);
    response.headers.set('Content-Security-Policy', csp);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    _status(response, HttpStatus.ok, mime, bytes.length);
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    response.add(bytes);
    await response.close();
  }

  Future<void> _serveMedia(
    HttpRequest request,
    OfficialAnkiMediaDecision decision,
  ) async {
    final response = request.response;
    final file = decision.file!;
    final mime = OfficialAnkiMime.mimeForName(
      file.uri.pathSegments.isEmpty ? '' : file.uri.pathSegments.last,
    );
    final range = OfficialAnkiHttpRange.parse(
      request.headers.value(HttpHeaders.rangeHeader),
      await file.length(),
    );
    _corsHeaders(response, mime);
    response.headers.set(HttpHeaders.cacheControlHeader, 'private, max-age=0');
    if (!range.satisfiable) {
      response.headers.set(HttpHeaders.contentRangeHeader, range.contentRange);
      _status(response, range.status, mime, 0);
      await response.close();
      return;
    }
    if (range.status == HttpStatus.partialContent) {
      response.headers.set(HttpHeaders.contentRangeHeader, range.contentRange);
    }
    _status(response, range.status, mime, range.contentLength);
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(file.openRead(range.start, range.end + 1));
    await response.close();
  }

  void _corsHeaders(HttpResponse response, String mime) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, 'null');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (OfficialAnkiMime.isUnknown(mime)) {
      response.headers.set('X-Content-Type-Options', 'nosniff');
    }
  }

  void _status(HttpResponse response, int status, String mime, int length) {
    response.statusCode = status;
    final encoding = OfficialAnkiMime.encodingForMime(mime);
    response.headers.contentType = encoding == null
        ? ContentType.parse(mime)
        : ContentType.parse('$mime; charset=$encoding');
    response.contentLength = length;
  }

  Future<void> _deny(HttpResponse response, int status, String reason) async {
    response.statusCode = status;
    response.reasonPhrase = reason;
    response.headers.contentType = ContentType.text;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.contentLength = 0;
    await response.close();
  }
}
