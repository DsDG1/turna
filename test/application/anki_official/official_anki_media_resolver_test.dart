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
      File('test/fixtures/anki_official/media_path_vectors.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    vectors = (raw['vectors'] as List).cast<Map<String, dynamic>>().map((item) {
      return item.map((key, value) => MapEntry(key, value));
    }).toList();
    for (final vector in vectors) {
      if (vector['allowed'] == true && vector['createFile'] == true) {
        try {
          File('${root.path}/${vector['expectedName']}').writeAsBytesSync([1]);
        } catch (_) {/* best-effort fixture seed */}
      }
    }
    resolver = OfficialAnkiMediaResolver(root);
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {/* best-effort temp cleanup */}
  });

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
        expect(decision.filename, vector['expectedName'],
            reason: '${vector['id']}');
        if (File('${root.path}/${vector['expectedName']}').existsSync()) {
          final resolved = resolver.resolveEncodedPath('/media/$encoded');
          expect(resolved.allowed, isTrue, reason: '${vector['id']} resolver');
          expect(resolved.file!.existsSync(), isTrue);
        }
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
    final hashUri = Uri.parse('https://anki.local/media/hash%23tag.bin');
    expect(OfficialAnkiMediaPath.encodedPathFromUri(hashUri),
        '/media/hash%23tag.bin');
    expect(resolver.resolveUri(hashUri).allowed, isTrue);
    final queryUri = Uri.parse('https://anki.local/media/question%3F.png');
    expect(OfficialAnkiMediaPath.encodedPathFromUri(queryUri),
        '/media/question%3F.png');
    if (!Platform.isWindows) {
      File('${root.path}/question?.png').writeAsBytesSync([1]);
      expect(resolver.resolveUri(queryUri).allowed, isTrue);
    }
  });

  test('rejects traversal, schemes, and absolute paths', () {
    expect(
        resolver.resolveUri(Uri.parse('file:///etc/passwd')).allowed, isFalse);
    expect(
        resolver.resolveUri(Uri.parse('content://media/x')).allowed, isFalse);
    expect(resolver.resolveUri(Uri.parse('http://anki.local/media/x')).allowed,
        isFalse);
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
    expect(OfficialAnkiMediaResolver.isDeniedScheme('javascript:alert(1)'),
        isTrue);
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
    expect(OfficialAnkiMediaResolver.isAllowedAsset('mathjax/tex-svg-full.js'),
        isTrue);
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
    expect(
        OfficialAnkiHttpRange.parse('bytes=0-99', 0).contentRange, 'bytes */0');
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

  test(
      'cross-language media path policy stays aligned across Dart, ArkTS, Kotlin, and Swift (T1)',
      () {
    final arkts =
        File('ohos/entry/src/main/ets/anki/AnkiMediaPath.ets').readAsStringSync();
    final kotlin = File(
      'android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiMediaPath.kt',
    ).readAsStringSync();
    final swift = File(
      'ios/Runner/AnkiReviewer/OfficialAnkiSchemeHandler.swift',
    ).readAsStringSync();
    final originServer = File(
      'ohos/entry/src/main/ets/anki/AnkiOriginServer.ets',
    ).readAsStringSync();

    for (final source in <String>[arkts, kotlin]) {
      for (final reason in const <String>[
        'empty_or_nul',
        'separator',
        'dotdot',
        'absolute',
        'double_encoding',
        'malformed_percent',
        'asset_name',
        'prefix',
      ]) {
        expect(source, contains(reason));
      }
    }
    for (final source in <String>[arkts, kotlin, swift]) {
      for (final residual in const <String>['%2f', '%5c', '%00', '%2e%2e']) {
        expect(source.toLowerCase(), contains(residual));
      }
      expect(source, contains('anki.local'));
    }

    // ArkTS classifyEncodedPath must allow valid media filenames and decode
    // multi-byte UTF-8 sequences with Latin-1 fallback (O1/T1 bug fix).
    expect(
      arkts,
      contains('return new RequestTarget(true, undefined, decision.filename);'),
    );
    expect(arkts, contains('decodeUtf8OrLatin1(units)'));
    // O1: AnkiOriginServer falls back to positioned fs.readSync when media is
    // not pre-pushed in the in-memory map. A failed read is its own reason;
    // it must not be reported as the old cache-miss code.
    expect(originServer, contains('readFileSlice('));
    expect(originServer, contains('fs.readSync(file.fd, buffer'));
    expect(originServer, contains('MEDIA_READ_FAILED'));
    expect(originServer, isNot(contains('MEDIA_NOT_PUSHED')));
  });

  test(
      'ArkTS AnkiMediaPath and AnkiHttp match Dart across all shared vectors (T1)',
      () {
    final nodeProbe = Process.runSync('node', const <String>['--version']);
    if (nodeProbe.exitCode != 0) {
      return;
    }
    final arktsMediaJs = _arktsToCommonJs(
      File('ohos/entry/src/main/ets/anki/AnkiMediaPath.ets').readAsStringSync(),
    );
    final arktsHttpJs = _arktsToCommonJs(
      File('ohos/entry/src/main/ets/anki/AnkiHttp.ets').readAsStringSync(),
    );
    final script = '''
$arktsMediaJs
$arktsHttpJs
const fs = require('fs');
const raw = JSON.parse(fs.readFileSync('test/fixtures/anki_official/media_path_vectors.json', 'utf8'));
const results = raw.vectors.map((v) => {
  const nameDecision = classifyEncodedName(v.encodedName);
  const pathTarget = classifyEncodedPath('/media/' + v.encodedName);
  return {
    id: v.id,
    allowed: nameDecision.allowed,
    filename: nameDecision.filename ?? null,
    reason: nameDecision.reason ?? null,
    pathAllowed: pathTarget.allowed,
    pathMediaName: pathTarget.mediaName ?? null,
  };
});
const rangeChecks = [
  parseRange('', 1000),
  parseRange('bytes=0-99', 1000),
  parseRange('bytes=100-', 1000),
  parseRange('bytes=-500', 1000),
  parseRange('bytes=0-99', 0),
  parseRange('bytes=50-40', 1000),
  parseRange('bytes=1000-1001', 1000),
  parseRange('bytes=0-99,200-300', 1000),
].map((r) => ({
  status: r.status,
  satisfiable: r.satisfiable,
  start: r.start,
  end: r.end,
  contentLength: r.contentLength,
  contentRange: r.contentRange ?? null,
}));
const mimeChecks = [
  mimeForName('cat.png'),
  mimeForName('voice.mp3'),
  mimeForName('clip.mp4'),
  mimeForName('font.woff2'),
  mimeForName('unknown.bin'),
  encodingForMime('image/png'),
  encodingForMime('text/css'),
];
process.stdout.write(JSON.stringify({ results, rangeChecks, mimeChecks }));
''';
    final run = Process.runSync(
      'node',
      <String>['-e', script],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(
      run.exitCode,
      0,
      reason: 'ArkTS vector runner failed: ${run.stderr}',
    );
    final payload =
        jsonDecode(run.stdout as String) as Map<String, dynamic>;
    final results =
        (payload['results'] as List).cast<Map<String, dynamic>>();
    expect(results.length, vectors.length);

    for (var i = 0; i < vectors.length; i++) {
      final vector = vectors[i];
      final actual = results[i];
      final expected = OfficialAnkiMediaPath.classifyEncodedName(
        vector['encodedName'] as String,
      );
      final expectedPath = OfficialAnkiMediaPath.classifyEncodedPath(
        '/media/${vector['encodedName']}',
      );
      expect(
        actual['allowed'],
        expected.allowed,
        reason: 'ArkTS allow mismatch on ${vector['id']}',
      );
      expect(
        actual['filename'],
        expected.filename,
        reason: 'ArkTS filename mismatch on ${vector['id']}',
      );
      expect(
        actual['reason'],
        expected.reason,
        reason: 'ArkTS reason mismatch on ${vector['id']}',
      );
      expect(
        actual['pathAllowed'],
        expectedPath.allowed,
        reason: 'ArkTS classifyEncodedPath mismatch on ${vector['id']}',
      );
      expect(
        actual['pathMediaName'],
        expectedPath.mediaName,
        reason: 'ArkTS classifyEncodedPath mediaName mismatch on ${vector['id']}',
      );
    }

    final rangeInputs = <(String?, int)>[
      (null, 1000),
      ('bytes=0-99', 1000),
      ('bytes=100-', 1000),
      ('bytes=-500', 1000),
      ('bytes=0-99', 0),
      ('bytes=50-40', 1000),
      ('bytes=1000-1001', 1000),
      ('bytes=0-99,200-300', 1000),
    ];
    final rangeChecks =
        (payload['rangeChecks'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < rangeInputs.length; i++) {
      final (header, total) = rangeInputs[i];
      final dartRange = OfficialAnkiHttpRange.parse(header, total);
      final arktsRange = rangeChecks[i];
      expect(arktsRange['status'], dartRange.status);
      expect(arktsRange['satisfiable'], dartRange.satisfiable);
      expect(arktsRange['start'], dartRange.start);
      expect(arktsRange['end'], dartRange.end);
      expect(arktsRange['contentLength'], dartRange.contentLength);
      expect(arktsRange['contentRange'], dartRange.contentRange);
    }
  });
}

String _arktsToCommonJs(String source) {
  return source
      .replaceAll(RegExp(r'^\s*export\s+', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*readonly\s+\w+.*$', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'(\w+)\?:\s*[A-Za-z0-9_<>\[\]\s|]+(?=[,)=])'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp(r'(\w+):\s*[A-Za-z0-9_<>\[\]\s|]+(?=[,)=;])'),
        (m) => m.group(1)!,
      )
      .replaceAllMapped(
        RegExp(r'\):\s*[A-Za-z0-9_<>\[\]\s|]+\s*\{'),
        (_) => ') {',
      );
}
