// Unit tests for [AnkiImporter] notetype parsing. Exposes the
// `_parseNotetypes` private path via [AnkiImporter.parseNotetypesForTest]
// so we can exercise the malformed-fields hardening without an `.apkg`
// fixture.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/anki/anki_importer.dart';

void main() {
  group('AnkiImporter._parseNotetypes', () {
    String modelsJsonFor(Map<int, Map<String, dynamic>> byMid) {
      return jsonEncode({
        for (final entry in byMid.entries) entry.key.toString(): entry.value,
      });
    }

    Map<String, dynamic> notetype({
      required List<dynamic> fields,
      String name = 'Model',
      List<dynamic>? templates,
      int type = 0,
      String css = '',
    }) =>
        {
          'name': name,
          'flds': fields,
          'tmpls': templates ??
              [
                {
                  'name': 'Card 1',
                  'qfmt': '{{Front}}',
                  'afmt': '{{Back}}',
                },
              ],
          'type': type,
          'css': css,
        };

    test('valid notetype with 3 fields parses unchanged', () {
      final modelsJson = modelsJsonFor({
        1: notetype(
          fields: [
            {'name': 'Front'},
            {'name': 'Back'},
            {'name': 'Extra'},
          ],
        ),
      });

      final result = AnkiImporter.parseNotetypesForTest(modelsJson);

      expect(result, hasLength(1));
      final nt = result[1]!;
      expect(nt.fieldNames, ['Front', 'Back', 'Extra']);
    });

    test('notetype with one malformed field is rejected entirely', () {
      // Regression: the old parser logged a warning and kept the notetype
      // with `fieldNames[1] == ''`, which silently shifted every later
      // field index when the renderer read note.fields[N] against
      // fieldNames[N]. The fix rejects the whole notetype.
      final modelsJson = modelsJsonFor({
        2: notetype(
          fields: [
            {'name': 'Front'},
            null, // malformed — not a Map
            {'name': 'Back'},
          ],
        ),
      });

      final result = AnkiImporter.parseNotetypesForTest(modelsJson);

      expect(result, isEmpty,
          reason: 'A notetype with any malformed field must be skipped');
    });

    test('notetype with a field missing the `name` key is rejected', () {
      final modelsJson = modelsJsonFor({
        3: notetype(
          fields: [
            {'name': 'Front'},
            {'ord': 1, 'size': 12}, // missing `name`
          ],
        ),
      });

      final result = AnkiImporter.parseNotetypesForTest(modelsJson);

      expect(result, isEmpty,
          reason:
              'A field without a `name` key cannot be safely indexed and '
              'must drop the entire notetype');
    });

    test('notetype with empty flds list is rejected', () {
      final modelsJson = modelsJsonFor({
        4: notetype(fields: const []),
      });

      final result = AnkiImporter.parseNotetypesForTest(modelsJson);

      expect(result, isEmpty);
    });

    test('a mix of valid and malformed notetypes keeps the valid ones',
        () {
      final modelsJson = modelsJsonFor({
        10: notetype(fields: [
          {'name': 'A'},
          {'name': 'B'},
        ]),
        11: notetype(fields: [
          {'name': 'C'},
          'not-a-map', // malformed
        ]),
        12: notetype(fields: [
          {'name': 'D'},
        ]),
      });

      final result = AnkiImporter.parseNotetypesForTest(modelsJson);

      expect(result.keys.toSet(), {10, 12});
      expect(result[10]!.fieldNames, ['A', 'B']);
      expect(result[12]!.fieldNames, ['D']);
    });
  });
}