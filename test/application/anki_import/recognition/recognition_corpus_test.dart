import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

/// Gold-standard corpus (doc 37 §6 P2): every case pins the archetype,
/// the band, and the field→role binding. Lexicon or rule changes must
/// update these expectations explicitly — and the full-result snapshot
/// underneath — so regressions surface as reviewable diffs.
void main() {
  final corpusDir = Directory('test/fixtures/anki_recognition/corpus');
  final cases = <Map<String, Object?>>[];
  for (final file in corpusDir.listSync().whereType<File>()) {
    cases.add(jsonDecode(file.readAsStringSync()) as Map<String, Object?>);
  }
  cases.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

  const recognizer = CardRecognizer();

  for (final entry in cases) {
    final id = entry['id'] as String;
    final description = entry['description'] as String;
    final schema =
        OfficialAnkiProjectionSchema.fromJson(
            (entry['schema'] as Map).cast<String, Object?>());
    final expected =
        (entry['expected'] as Map).cast<String, Object?>();
    final result = recognizer.recognizeNotetype(schema);

    test('corpus $id: $description', () {
      expect(
        result.archetype.name,
        expected['archetype'] as String,
        reason: 'archetype mismatch for $id',
      );
      expect(
        result.band.name,
        expected['band'] as String,
        reason: 'band mismatch for $id (confidence ${result.confidence})',
      );
      final roles = (expected['roles'] as Map).cast<String, String>();
      for (final field in roles.keys) {
        final index = schema.fieldNames.indexOf(field);
        expect(index, greaterThanOrEqualTo(0), reason: 'unknown field $field');
        final bound = result.roles.values.where((b) => b.fieldIndex == index);
        expect(
          bound,
          isNotEmpty,
          reason: '$id: field $field has no binding',
        );
        expect(
          bound.first.role.name,
          roles[field],
          reason: '$id: field $field bound to ${bound.first.role.name}',
        );
      }
    });
  }

  test('corpus snapshot matches committed golden', () {
    expect(cases, isNotEmpty, reason: 'corpus fixtures missing');
    final snapshotFile =
        File('test/fixtures/anki_recognition/snapshots.json');
    final actual = <String, Object?>{};
    for (final entry in cases) {
      final id = entry['id'] as String;
      final schema = OfficialAnkiProjectionSchema.fromJson(
          (entry['schema'] as Map).cast<String, Object?>());
      final result = recognizer.recognizeNotetype(schema);
      actual[id] = {
        'archetype': result.archetype.name,
        'confidence': result.confidence.toStringAsFixed(3),
        'band': result.band.name,
        'roles': {
          for (final role in result.roles.keys)
            role.name: {
              'field': result.roles[role]!.fieldName,
              'confidence':
                  result.roles[role]!.confidence.toStringAsFixed(3),
            },
        },
        'evidence': [
          for (final item in result.evidence)
            '${item.signal} w=${item.weight.toStringAsFixed(2)}',
        ],
      };
    }
    if (Platform.environment['UPDATE_RECOGNIZER_SNAPSHOTS'] == '1') {
      snapshotFile.parent.createSync(recursive: true);
      snapshotFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(actual),
      );
      return;
    }
    expect(
      snapshotFile.existsSync(),
      isTrue,
      reason: 'snapshot missing; run with UPDATE_RECOGNIZER_SNAPSHOTS=1',
    );
    final expected = jsonDecode(snapshotFile.readAsStringSync())
        as Map<String, Object?>;
    expect(actual, expected);
  });
}
