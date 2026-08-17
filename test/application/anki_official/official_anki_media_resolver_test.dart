import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/render/official_anki_http_range.dart';
import 'package:turna/application/anki_official/render/official_anki_media_path.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_mime.dart';

void main() {
  late Directory root;
  late OfficialAnkiMediaResolver resolver;
  late List<Map<String, Object?>> vectors;

  setUp(() {
    root = Directory.systemTemp.createTempSync('turna-media-');
    final raw = jsonDecode(
      File('test/fixtures/anki_official/media_path_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    vectors = (raw['vectors'] as List).cast<Map<String, dynamic>>().map((item) {
      return item.map((key, value) => MapEntry(key, value));
    }).toList();
    for (final vector in vectors) {
      if (vector['allowed'] == true && vector['createFile'] == true) {
        File('${root.path}/${vector['expectedName']}').writeAsBytesSync([1]);
      }
    }
    resolver = OfficialAnkiMediaResolver(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('shared media path vectors decode once and match allow/deny', () {
    expect(vectors.length, greaterThanOrEqualTo(40));
    for (final vector in vectors) {
      final encoded = vector['encodedName'] as String;
      final allowed = vector['allowed'] == true;
      final decision = OfficialAnkiMediaPath.classifyEncodedName(encoded);
      expect(
        decision.allowed,
        allowed,
        reason: '${vector['id']} encoded=$encoded reason=${decision.reason}',
      );
      if (allowed) {
        expect(decision.filename, vector['expectedName'], reason: '${vector['id']}');
        final resolved = resolver.resolveEncodedPath('/media/$encoded');
        expect(resolved.allowed, isTrue, reason: '${vector['id']} resolver');
        expect(resolved.file!.existsSync(), isTrue);
      } else {
        expect(
          resolver.resolveEncodedPath('/media/$encoded').allowed,
          isFalse,
          reason: '${vector['id']} resolver deny',
        );
      }
    }
  });

  test('encodedPath is used so # and ? are not treated as fragment/query', () {
    File('${root.path}/hash#tag.bin').writeAsBytesSync([1]);
    File('${root.path}/question?.png').writeAsBytesSync([1]);
    final hashUri = Uri.parse('https://anki.local/media/hash%23tag.bin');
    expect(OfficialAnkiMediaPath.encodedPathFromUri(hashUri), '/media/hash%23tag.bin');
    expect(resolver.resolveUri(hashUri).allowed, isTrue);
    final queryUri = Uri.parse('https://anki.local/media/question%3F.png');
    expect(OfficialAnkiMediaPath.encodedPathFromUri(queryUri), '/media/question%3F.png');
    expect(resolver.resolveUri(queryUri).allowed, isTrue);
  });

  test('rejects traversal, schemes, and absolute paths', () {
    expect(resolver.resolveUri(Uri.parse('file:///etc/passwd')).allowed, isFalse);
    expect(resolver.resolveUri(Uri.parse('content://media/x')).allowed, isFalse);
    expect(resolver.resolveUri(Uri.parse('http://anki.local/media/x')).allowed, isFalse);
    expect(
      resolver.resolveUri(Uri.parse('https://evil.example/media/x')).allowed,
      isFalse,
    );
    expect(
      resolver.resolveEncodedPath('/media/../hello%20world.png').allowed,
      isFalse,
    );
    expect(resolver.resolveRelativeName('../hello world.png').allowed, isFalse);
    expect(resolver.resolveRelativeName('/etc/passwd').allowed, isFalse);
    expect(OfficialAnkiMediaResolver.isDeniedScheme('intent://x'), isTrue);
    expect(OfficialAnkiMediaResolver.isDeniedScheme('javascript:alert(1)'), isTrue);
    expect(OfficialAnkiMediaResolver.isDeniedScheme('ws://anki.local'), isTrue);
  });

  test('foo..bar is allowed because .. is not a path segment', () {
    File('${root.path}/foo..bar.png').writeAsBytesSync([9]);
    expect(resolver.resolveRelativeName('foo..bar.png').allowed, isTrue);
    expect(
      OfficialAnkiMediaPath.classifyDecodedName('foo..bar.png').allowed,
      isTrue,
    );
  });

  test('directory and symlink escape are rejected', () {
    Directory('${root.path}/subdir').createSync();
    expect(resolver.resolveRelativeName('subdir').allowed, isFalse);
    final outside = File('${root.parent.path}/outside-secret.txt')
      ..writeAsStringSync('nope');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync();
    });
    final link = Link('${root.path}/escape.bin');
    link.createSync(outside.path);
    expect(resolver.resolveRelativeName('escape.bin').allowed, isFalse);
  });

  test('fixed reviewer assets stay inside the allowlist', () {
    expect(OfficialAnkiMediaResolver.isAllowedAsset('reviewer.html'), isTrue);
    expect(OfficialAnkiMediaResolver.isAllowedAsset('mathjax/tex-svg-full.js'), isTrue);
    expect(OfficialAnkiMediaResolver.isAllowedAsset('card-frame.html'), isTrue);
    expect(OfficialAnkiMediaResolver.isAllowedAsset('../x.js'), isFalse);
    expect(OfficialAnkiMediaResolver.isAllowedAsset('/etc/passwd'), isFalse);
  });

  test('range parser bounds 0/1/1000 byte files and rejects multi-range', () {
    expect(OfficialAnkiHttpRange.parse(null, 1000).status, 200);
    expect(OfficialAnkiHttpRange.parse('bytes=0-99', 1000).contentLength, 100);
    expect(OfficialAnkiHttpRange.parse('bytes=100-', 1000).start, 100);
    expect(OfficialAnkiHttpRange.parse('bytes=100-', 1000).end, 999);
    expect(OfficialAnkiHttpRange.parse('bytes=-500', 1000).start, 500);
    expect(OfficialAnkiHttpRange.parse('bytes=-500', 1000).contentLength, 500);
    expect(OfficialAnkiHttpRange.parse('bytes=0-99', 0).status, 416);
    expect(OfficialAnkiHttpRange.parse('bytes=0-99', 0).contentRange, 'bytes */0');
    expect(OfficialAnkiHttpRange.parse('bytes=50-40', 1000).status, 416);
    expect(OfficialAnkiHttpRange.parse('bytes=1000-1001', 1000).status, 416);
    expect(OfficialAnkiHttpRange.parse('bytes=0-99,200-300', 1000).status, 416);
    expect(OfficialAnkiHttpRange.parse('bytes=0-0', 1).contentLength, 1);
    final empty = OfficialAnkiHttpRange.parse('bytes=0-0', 0);
    expect(empty.satisfiable, isFalse);
    final bytes = List<int>.generate(1000, (i) => i % 256);
    final slice = OfficialAnkiHttpRange.parse('bytes=0-99', 1000).slice(bytes);
    expect(slice, bytes.sublist(0, 100));
    expect(slice.length, 100);
  });

  test('mime encoding is null for binary and utf-8 for text', () {
    expect(OfficialAnkiMime.encodingForMime('image/png'), isNull);
    expect(OfficialAnkiMime.encodingForMime('audio/mpeg'), isNull);
    expect(OfficialAnkiMime.encodingForMime('video/mp4'), isNull);
    expect(OfficialAnkiMime.encodingForMime('font/woff2'), isNull);
    expect(OfficialAnkiMime.encodingForMime('text/css'), 'utf-8');
    expect(OfficialAnkiMime.encodingForMime('text/javascript'), 'utf-8');
    expect(OfficialAnkiMime.mimeForName('x.bin'), 'application/octet-stream');
    expect(OfficialAnkiMime.isUnknown('application/octet-stream'), isTrue);
  });
}
