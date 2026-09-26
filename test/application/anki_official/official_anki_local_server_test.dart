import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/render/official_anki_local_server.dart';

void main() {
  late Directory mediaRoot;
  late OfficialAnkiLocalServer server;

  Map<String, String> assets = <String, String>{
    'reviewer.html': '<html><base href="https://anki.local/media/"></html>',
    'mathjax/tex-svg-full.js': 'var mathjax = true;',
  };

  setUp(() async {
    mediaRoot = Directory.systemTemp.createTempSync('turna-local-server-');
    File('${mediaRoot.path}/hello world.png')
        .writeAsBytesSync(List<int>.generate(64, (i) => i));
    server = await OfficialAnkiLocalServer.start(
      mediaRoot: mediaRoot,
      assetLoader: (name) async {
        final text = assets[name];
        if (text == null) return null;
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
      },
    );
  });

  tearDown(() async {
    await server.dispose();
    try {
      mediaRoot.deleteSync(recursive: true);
    } catch (_) {
      // Temp cleanup is best-effort.
    }
  });

  Future<HttpClientResponse> get(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
  }) async {
    final client = HttpClient();
    final request = await client.openUrl(
      method,
      Uri.parse('${server.origin}$path'),
    );
    headers?.forEach(request.headers.set);
    final response = await request.close();
    return response;
  }

  test('serves reviewer shell with anki.local rewritten to loopback origin',
      () async {
    final response = await get('/assets/reviewer.html');
    expect(response.statusCode, HttpStatus.ok);
    final body = await utf8.decoder.bind(response).join();
    expect(body, contains('${server.origin}/media/'));
    expect(body, isNot(contains('anki.local')));
    expect(
      response.headers.value('Content-Security-Policy'),
      contains(server.origin),
    );
  });

  test('denies unsafe asset names and missing assets', () async {
    final traversal = await get('/assets/../secret');
    expect(traversal.statusCode, HttpStatus.forbidden);
    clientClose(traversal);

    final missing = await get('/assets/nope.js');
    expect(missing.statusCode, HttpStatus.notFound);
    clientClose(missing);

    final mathjaxMissing = await get('/assets/mathjax/other.js');
    expect(mathjaxMissing.statusCode, HttpStatus.notFound);
    expect(mathjaxMissing.reasonPhrase, 'MATHJAX_ASSET_MISSING');
    clientClose(mathjaxMissing);
  });

  test('serves media with percent-decoded names, mime and full range',
      () async {
    final response = await get('/media/hello%20world.png');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('Accept-Ranges'), 'bytes');
    expect(response.headers.value('Access-Control-Allow-Origin'), 'null');
    expect(response.headers.contentType?.mimeType, 'image/png');
    final bytes = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    expect(bytes.length, 64);
  });

  test('honors byte ranges and rejects unsatisfiable ones', () async {
    final partial = await get(
      '/media/hello%20world.png',
      headers: {'Range': 'bytes=10-19'},
    );
    expect(partial.statusCode, HttpStatus.partialContent);
    expect(partial.headers.value('Content-Range'), 'bytes 10-19/64');
    final bytes = await partial.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    expect(bytes, List<int>.generate(10, (i) => 10 + i));

    final unsatisfiable = await get(
      '/media/hello%20world.png',
      headers: {'Range': 'bytes=100-200'},
    );
    expect(unsatisfiable.statusCode, 416);
    clientClose(unsatisfiable);
  });

  test('rejects traversal and missing media', () async {
    final traversal = await get('/media/..%2Fescape.txt');
    expect(traversal.statusCode, HttpStatus.forbidden);
    clientClose(traversal);

    final missing = await get('/media/nope.png');
    expect(missing.statusCode, HttpStatus.notFound);
    clientClose(missing);

    final root = await get('/');
    expect(root.statusCode, HttpStatus.forbidden);
    clientClose(root);
  });
}

void clientClose(HttpClientResponse response) {
  unawaited(response.drain<void>());
}
