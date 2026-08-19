import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';

void main() {
  group('P5-E Wave 1 Architecture & Forbidden Imports', () {
    test('LegacyAnkiIdentifiers parses wordId, sectionId, and prefix accurately', () {
      expect(LegacyAnkiIdentifiers.ankiPrefix, 'anki-');
      expect(
        LegacyAnkiIdentifiers.importIdFromWordId('anki-12345678-c100'),
        '12345678',
      );
      expect(
        LegacyAnkiIdentifiers.importIdFromSectionId('anki-12345678-s0'),
        '12345678',
      );
      expect(
        LegacyAnkiIdentifiers.importIdFromWordId('plain_word_id'),
        '',
      );
      expect(
        LegacyAnkiIdentifiers.importIdFromSectionId('custom_section'),
        '',
      );
    });

    test('lib/application/anki_official/ does not import legacy anki except allowed adapters', () {
      final officialDir = Directory('lib/application/anki_official');
      expect(officialDir.existsSync(), isTrue);

      final allowedFiles = {
        'anki_import_facade.dart', // fallback for non-official import
        'official_anki_new_import_cutover.dart', // projection assembler adapter
        'official_anki_internal_page.dart', // internal debug / side-by-side test
      };

      final violations = <String>[];

      for (final entity in officialDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final filename = entity.uri.pathSegments.last;
        if (allowedFiles.contains(filename)) continue;

        final content = entity.readAsStringSync();
        final lines = content.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('import ') &&
              (line.contains('package:turna/application/anki/') ||
                  line.contains('package:turna/views/anki/'))) {
            violations.add('${entity.path}:${i + 1}: $line');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'P5-E Wave 1 forbids official Core from directly importing legacy anki implementation files:\n${violations.join('\n')}',
      );
    });

    test('lib/ directory strictly contains NO AnkiWeb / sync imports or API endpoints', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final forbiddenKeywords = [
        'ankiweb.net',
        'ankiweb_sync',
        'AnkiWebSync',
        'anki_web_sync',
      ];

      final violations = <String>[];

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        for (final kw in forbiddenKeywords) {
          if (content.contains(kw)) {
            violations.add('${entity.path} contains forbidden AnkiWeb reference: "$kw"');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Phase 6 is cancelled; production code must not contain AnkiWeb sync logic:\n${violations.join('\n')}',
      );
    });

    test('ReviewProgressProvider and OfficialAnkiHomeDueSync decouple from legacy assembler', () {
      final progressFile = File('lib/application/review_progress_provider.dart');
      final homeDueFile = File('lib/application/anki_official/engine/official_anki_home_due.dart');
      final gateFile = File('lib/views/anki/anki_official_review_gate.dart');
      final routerFile = File('lib/application/anki_official/migration/official_anki_production_router.dart');

      for (final file in [progressFile, homeDueFile, gateFile, routerFile]) {
        expect(file.existsSync(), isTrue);
        final content = file.readAsStringSync();
        expect(
          content.contains("import 'package:turna/application/anki/anki_review_assembler.dart';"),
          isFalse,
          reason: '${file.path} should not import legacy anki_review_assembler.dart',
        );
      }
    });
  });
}
