import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Verify committed official Anki spike fixtures against manifest.json.
/// Usage: dart run tool/official_anki_spike/verify_fixture_results.dart
void main(List<String> args) {
  final root = Directory.current.path;
  final fixtureRoot = p.join(root, 'test', 'fixtures', 'anki_official');
  final manifestFile = File(p.join(fixtureRoot, 'manifest.json'));
  if (!manifestFile.existsSync()) {
    stderr.writeln('missing $manifestFile — run generate_fixtures.sh first');
    exitCode = 2;
    return;
  }
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = (manifest['packages'] as List<dynamic>).cast<Map<String, dynamic>>();
  var failed = 0;
  for (final pkg in packages) {
    if (pkg['generated'] == true) {
      stdout.writeln('skip generated ${pkg['file']}');
      continue;
    }
    final rel = pkg['file'] as String;
    final file = File(p.join(fixtureRoot, 'packages', rel));
    if (!file.existsSync()) {
      stderr.writeln('missing package $rel');
      failed += 1;
      continue;
    }
    final digest = sha256.convert(file.readAsBytesSync()).toString();
    if (digest != pkg['sha256']) {
      stderr.writeln('sha256 mismatch for $rel\n  want ${pkg['sha256']}\n  got  $digest');
      failed += 1;
    }
    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final names = archive.map((e) => e.name).toSet();
    final hasCollection = names.contains('collection.anki2') ||
        names.contains('collection.anki21b');
    if (!hasCollection) {
      stderr.writeln('$rel has no collection.anki2/anki21b');
      failed += 1;
    }
    if (pkg['legacy'] == true && !names.contains('collection.anki2')) {
      stderr.writeln('$rel is marked legacy but has no collection.anki2');
      failed += 1;
    }
    final expectedRel = pkg['expected'] as String?;
    if (expectedRel != null) {
      final expected = File(p.join(fixtureRoot, expectedRel));
      if (!expected.existsSync()) {
        stderr.writeln('missing expected render $expectedRel');
        failed += 1;
      } else {
        failed += _checkAssertions(rel, expected, pkg);
      }
    }
  }
  if (failed > 0) {
    stderr.writeln('$failed fixture check(s) failed');
    exitCode = 1;
    return;
  }
  stdout.writeln('ok ${packages.where((p) => p['generated'] != true).length} packages');
}

int _checkAssertions(
  String rel,
  File expectedFile,
  Map<String, dynamic> pkg,
) {
  final payload = jsonDecode(expectedFile.readAsStringSync()) as Map<String, dynamic>;
  final cards = (payload['cards'] as List<dynamic>).cast<Map<String, dynamic>>();
  final expectedCards = pkg['expectedCards'] as int;
  var failed = 0;
  if (cards.length != expectedCards) {
    stderr.writeln('$rel expected $expectedCards cards, golden has ${cards.length}');
    failed += 1;
  }
  final blob = cards
      .map((c) =>
          '${c['questionHtml']}\n${c['answerHtml']}\n${c['css']}')
      .join('\n');
  for (final raw in (pkg['assertions'] as List<dynamic>).cast<String>()) {
    const prefix = 'question-contains:';
    const answer = 'answer-contains:';
    const css = 'css-contains:';
    if (raw.startsWith(prefix) &&
        !cards.any((c) => (c['questionHtml'] as String).contains(raw.substring(prefix.length)))) {
      stderr.writeln('$rel missing $raw');
      failed += 1;
    } else if (raw.startsWith(answer) &&
        !cards.any((c) => (c['answerHtml'] as String).contains(raw.substring(answer.length)))) {
      stderr.writeln('$rel missing $raw');
      failed += 1;
    } else if (raw.startsWith(css) && !blob.contains(raw.substring(css.length))) {
      stderr.writeln('$rel missing $raw');
      failed += 1;
    }
  }
  return failed;
}
