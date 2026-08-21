import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Anki unification architecture guards', () {
    test('new unification surfaces do not import scheduler DAOs', () {
      final violations = [
        ..._scan(
          Directory('lib/domain/anki'),
          forbidden: _schedulerDaos,
        ),
        ..._scan(
          Directory('lib/application/anki/unification'),
          forbidden: _schedulerDaos,
        ),
        ..._scanFiles(
          const [
            'lib/application/anki/study_session_controller.dart',
            'lib/application/anki/anki_study_session_host.dart',
            'lib/application/anki/formal_review_launcher.dart',
            'lib/application/anki/unified_anki_import_orchestrator.dart',
            'lib/application/anki/anki_unification_migration.dart',
            'lib/application/anki/study_product_analytics.dart',
            'lib/views/review/components/study_card_surface.dart',
            'lib/views/anki_official/official_anki_practice_review_surface.dart',
          ],
          forbidden: _schedulerDaos,
        ),
      ];
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('interaction renderers do not write SRS or official scheduler', () {
      final violations = _scan(
        Directory('lib/views/lesson/components/interactions'),
        forbidden: const [
          "package:turna/application/srs_provider.dart",
          "package:turna/domain/review/official_anki_review_ledger.dart",
          "package:turna/application/anki_official/engine/official_anki_review_session.dart",
        ],
      );
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('new unification domain has no raw quality API', () {
      final dir = Directory('lib/domain/anki');
      expect(dir.existsSync(), isTrue);
      final violations = <String>[];
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        if (text.contains('int quality') || text.contains('ReviewQuality')) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('StudySessionController does not infer source from id prefixes', () {
      final text =
          File('lib/application/anki/study_session_controller.dart')
              .readAsStringSync();
      expect(text.contains("startsWith('anki-')"), isFalse);
      expect(text.contains("startsWith('official-anki-')"), isFalse);
    });

    test('new projection policy never returns multiple active kinds', () {
      final text = File(
        'lib/application/anki_official/projection/official_anki_projection_payloads.dart',
      ).readAsStringSync();
      expect(text.contains('list.add(OfficialAnkiProjectionKind.multipleChoice)'), isFalse);
      expect(text.contains('CardPresentationPolicy'), isTrue);
    });

    test('formal review path does not re-run practice classifier or four-rating',
        () {
      const paths = [
        'lib/views/anki_official/official_anki_review_page.dart',
        'lib/views/anki_official/official_anki_practice_review_surface.dart',
        'lib/views/anki/anki_review_session_page.dart',
        'lib/views/anki/anki_official_review_gate.dart',
        'lib/views/review/unified_review_page.dart',
        'lib/application/anki/anki_study_session_host.dart',
        'lib/application/anki/formal_review_launcher.dart',
      ];
      for (final path in paths) {
        final text = File(path).readAsStringSync();
        expect(
          text.contains(
            "package:turna/application/anki_practice/card_classifier.dart",
          ),
          isFalse,
          reason: '$path re-imports runtime classifier',
        );
        expect(text.contains('reviewHard'), isFalse, reason: path);
        expect(text.contains('reviewEasy'), isFalse, reason: path);
        expect(text.contains('int quality'), isFalse, reason: path);
      }
    });
  });
}

const _schedulerDaos = [
  "package:turna/data/srs_state_dao.dart",
  "package:turna/data/review_history_dao.dart",
  "package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart",
];

List<String> _scanFiles(List<String> paths, {required List<String> forbidden}) {
  final violations = <String>[];
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      violations.add('missing $path');
      continue;
    }
    final content = file.readAsStringSync();
    for (final needle in forbidden) {
      if (content.contains("import '$needle'")) {
        violations.add('$path imports $needle');
      }
    }
  }
  return violations;
}

List<String> _scan(Directory dir, {required List<String> forbidden}) {
  final violations = <String>[];
  if (!dir.existsSync()) return violations;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final content = entity.readAsStringSync();
    for (final needle in forbidden) {
      if (content.contains("import '$needle'")) {
        violations.add('${entity.path} imports $needle');
      }
    }
  }
  return violations;
}
