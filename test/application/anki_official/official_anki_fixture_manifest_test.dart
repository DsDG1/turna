import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final fixtureRoot = p.join('test', 'fixtures', 'anki_official');
  final manifestFile = File(p.join(fixtureRoot, 'manifest.json'));

  test('official Anki fixtures exist and match the frozen manifest', () {
    expect(manifestFile.existsSync(), isTrue, reason: 'run generate_fixtures.sh');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['fixtureVersion'], 1);
    expect(manifest['generatedWithAnkiCommit'], isNotEmpty);

    final packages =
        (manifest['packages'] as List<dynamic>).cast<Map<String, dynamic>>();
    final committed = packages.where((pkg) => pkg['generated'] != true).toList();
    expect(committed, isNotEmpty);

    for (final pkg in committed) {
      final file = File(p.join(fixtureRoot, 'packages', pkg['file'] as String));
      expect(file.existsSync(), isTrue, reason: pkg['file'] as String);
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        pkg['sha256'],
        reason: pkg['file'] as String,
      );
      final names = ZipDecoder()
          .decodeBytes(file.readAsBytesSync())
          .map((entry) => entry.name)
          .toSet();
      expect(
        names.contains('collection.anki2') || names.contains('collection.anki21b'),
        isTrue,
        reason: pkg['file'] as String,
      );
      if (pkg['legacy'] == true) {
        expect(names.contains('collection.anki2'), isTrue);
      }
      final expectedRel = pkg['expected'] as String?;
      if (expectedRel != null) {
        final expected = File(p.join(fixtureRoot, expectedRel));
        expect(expected.existsSync(), isTrue, reason: expectedRel);
        final cards = (jsonDecode(expected.readAsStringSync())
            as Map<String, dynamic>)['cards'] as List<dynamic>;
        expect(cards, hasLength(pkg['expectedCards']));
      }
    }
  });
}
