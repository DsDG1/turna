import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Official Anki architecture guards', () {
    test('new unification surfaces do not import scheduler DAOs', () {
      final violations = [
        ..._scan(
          Directory('lib/domain/anki'),
          forbidden: _schedulerDaos,
        ),
        ..._scanFiles(
          const [
            'lib/application/study_session/study_session_controller.dart',
            'lib/application/study_session/anki_study_session_host.dart',
            'lib/application/anki_official/review/formal_review_launcher.dart',
            'lib/application/study_session/study_product_analytics.dart',
            'lib/views/review/components/study_card_surface.dart',
            // Doc 39 P1-A: the orphan review page/practice surface live on
            // only as test/support fixtures; keep scanning them there.
            'test/support/official_anki_practice_review_surface_fixture.dart',
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
          File('lib/application/study_session/study_session_controller.dart')
              .readAsStringSync();
      expect(text.contains("startsWith('anki-')"), isFalse);
      expect(text.contains("startsWith('official-anki-')"), isFalse);
    });

    test('new projection policy never returns multiple active kinds', () {
      final text = File(
        'lib/application/anki_official/projection/official_anki_projection_payloads.dart',
      ).readAsStringSync();
      expect(text.contains('list.add(OfficialAnkiProjectionKind.multipleChoice)'), isFalse);
      expect(text.contains('OfficialAnkiPresentationPolicy'), isTrue);
    });

    test('formal review path does not re-run practice classifier or four-rating',
        () {
      const paths = [
        // Doc 39 P1-A: orphan review page/surface moved to test/support.
        'test/support/official_anki_review_fixture.dart',
        'test/support/official_anki_practice_review_surface_fixture.dart',
        'lib/views/anki/anki_review_session_page.dart',
        'lib/views/anki/anki_official_review_gate.dart',
        'lib/views/review/unified_review_page.dart',
        'lib/application/study_session/anki_study_session_host.dart',
        'lib/application/anki_official/review/formal_review_launcher.dart',
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

    // Doc 34 W9 §13.3 / doc 35 L1 — parser-layer deletion guards.
    // Doc 37 P5 — old recognizer deletion guards.
    test('legacy recognizer modules stay deleted (doc 37)', () {
      const deleted = [
        'lib/application/anki_official/projection/official_anki_projection_mapper.dart',
        'lib/application/anki_official/projection/card_presentation_policy.dart',
        'lib/application/anki_practice/card_classifier.dart',
        'lib/application/anki_practice/card_classifier_models.dart',
        'lib/application/anki_practice/embedded_options.dart',
        'lib/application/anki_practice/card_text.dart',
      ];
      for (final path in deleted) {
        expect(File(path).existsSync(), isFalse,
            reason: '$path was resurrected');
      }
      final libDir = Directory('lib');
      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        expect(text.contains('AnkiPracticeShape'), isFalse,
            reason: '${file.path} references the deleted shape enum');
        expect(text.contains('OfficialAnkiFieldRole'), isFalse,
            reason: '${file.path} references the deleted role enum');
      }
    });

    // Doc 38 P1-A — fixture pilot scaffold stays deleted.
    test('fixture pilot cluster stays deleted (doc 38)', () {
      const deleted = [
        'lib/application/anki_official/migration/official_anki_fixture_pilot_saga.dart',
        'lib/application/anki_official/migration/official_anki_fixture_rollback_drill.dart',
        'lib/application/anki_official/migration/official_anki_user_allowlist.dart',
        'lib/application/anki_official/official_anki_internal_page.dart',
      ];
      for (final path in deleted) {
        expect(File(path).existsSync(), isFalse,
            reason: '$path was resurrected');
      }
      final libDir = Directory('lib');
      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        expect(text.contains('isFixturePilotSource'), isFalse,
            reason: '${file.path} references the deleted fixture pilot gate');
        expect(text.contains('p5c-fixture-'), isFalse,
            reason: '${file.path} references the deleted fixture namespace');
      }
    });

    // Doc 39 P1 — dead-surface deletion guards (batch 2).
    test('doc 39 batch-2 dead surfaces stay deleted', () {
      for (final path in const [
        // P1-A: orphan review page (lives on as test/support fixture only).
        'lib/views/anki_official/official_anki_review_page.dart',
        'lib/views/anki_official/official_anki_practice_review_surface.dart',
        // P1-B: migration preview cluster.
        'lib/application/anki_official/migration/official_anki_preview_loader.dart',
        'lib/views/anki_official/official_anki_migration_preview_page.dart',
      ]) {
        expect(File(path).existsSync(), isFalse,
            reason: '$path was resurrected');
      }
      final libDir = Directory('lib');
      const needles = [
        // P1-C: unified orchestrator legacy path.
        'UnifiedAnkiImportRequest',
        'persistIdentity',
        // P1-F: audio staging/swap family.
        'swapStagedMedia',
        'stagingImportId',
        'rollbackMediaSwap',
        'finalizeMediaSwap',
        // P1-E: describeNextStates Dart call face.
        'describeNextStates',
        // P1-F: retired introduction repository.
        'CardIntroductionRepository',
      ];
      for (final file in libDir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final text = file.readAsStringSync();
        // Allow doc comments that document the deletion itself.
        final withoutComments = text
            .replaceAll(RegExp(r'//.*'), '')
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
        for (final needle in needles) {
          expect(
            withoutComments.contains(needle),
            isFalse,
            reason: '${file.path} resurrected $needle',
          );
        }
      }
    });

    // Doc 38 P1-B/C — the NoteStore/imports write side stays deleted.
    test('anki dao write side stays deleted (doc 38)', () {
      final dao = File('lib/data/anki_note_dao.dart').readAsStringSync();
      for (final member in [
        'replaceDeckIndex',
        'replaceImportIssues',
        'replacePracticeProjections',
        'deckIdsIncludingDescendants',
        'upsertNotetype',
        'upsertNote',
        'upsertCardMeta',
        'cardMetaByWordId',
        'wordIdsForDecks',
        'clearBuriedBefore',
        'flaggedCards',
        'AnkiNotetypeRecord',
        'AnkiTemplate',
      ]) {
        expect(dao.contains(member), isFalse,
            reason: 'anki_note_dao.dart resurrected writer $member');
      }
      final imports = File('lib/data/anki_import_dao.dart').readAsStringSync();
      for (final member in [
        'Future<void> upsert(',
        'markComplete',
        'markFailed',
        'markAiEnhanced',
      ]) {
        expect(imports.contains(member), isFalse,
            reason: 'anki_import_dao.dart resurrected writer $member');
      }
    });

    test('execution planner is strictly three-valued (no legacyOnly)', () {
      final text = File(
        'lib/application/anki_official/import/anki_import_execution_plan.dart',
      ).readAsStringSync();
      expect(text.contains('legacyOnly'), isFalse);
      expect(text.contains('allowLegacyOnly'), isFalse);

      // Behavioral matrix lives in
      // test/application/anki_official/anki_import_execution_plan_test.dart
      // (officialFirst / failClosed / unsupported).
      final planTest = File(
        'test/application/anki_official/anki_import_execution_plan_test.dart',
      ).readAsStringSync();
      expect(planTest.contains('legacyOnly'), isFalse);

      // The page is a shell; the wizard never opts into a Legacy writer.
      final importScreen =
          File('lib/views/anki/anki_import_screen.dart').readAsStringSync();
      final controller = File(
        'lib/application/anki_import/anki_import_controller.dart',
      ).readAsStringSync();
      final deps = File(
        'lib/application/anki_import/anki_import_dependencies.dart',
      ).readAsStringSync();
      for (final text in [importScreen, controller, deps]) {
        expect(
          text.contains('allowLegacyOnly: true'),
          isFalse,
          reason: 'production import path must not opt into legacyOnly',
        );
      }

      // W0-03: commit must reuse the pick-time plan, not re-read flags.
      final commitStart = controller.indexOf('Future<void> commit()');
      expect(commitStart, greaterThanOrEqualTo(0));
      final commitEnd = controller.indexOf('void _finishCommit');
      expect(commitEnd, greaterThan(commitStart));
      final commitBody = controller.substring(commitStart, commitEnd);
      expect(
        commitBody.contains('planFor'),
        isFalse,
        reason: 'W0-03: commit reuses the frozen preview.plan',
      );
      expect(commitBody.contains('preview.plan'), isTrue);
    });

    // Doc 35 L1 — the Dart .apkg parser layer must stay deleted.
    test('legacy parser layer stays deleted (doc 35 L1)', () {
      for (final path in const [
        'lib/application/anki/anki_importer.dart',
        'lib/application/anki/anki_deck_assembler.dart',
        'lib/application/anki/anki_card_adapter.dart',
        'lib/application/anki/anki_organization_resolver.dart',
        'lib/application/anki/anki_render_policy.dart',
        'lib/application/anki/anki_sample_deck.dart',
        'lib/application/anki/anki_srs_migrator.dart',
        'lib/application/anki/card_recognition_pipeline.dart',
        'lib/application/anki/legacy_anki_import_executor.dart',
        'lib/application/anki/anki_import_platform_io.dart',
        'lib/application/anki/anki_import_platform_stub.dart',
        'lib/application/anki/import_wizard/legacy_anki_import_flow.dart',
        'lib/application/anki/import_wizard/question_type.dart',
        'lib/application/anki/import_wizard/notetype_mapping_util.dart',
        'lib/views/anki/import_wizard/legacy_anki_import_preview.dart',
        'lib/views/anki/import_wizard/anki_notetype_mapping_editor.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: '$path was revived');
      }
      // No resurrection through imports anywhere in lib/.
      final violations = <String>[];
      final needles = [
        RegExp(r'[^a-zA-Z]AnkiImporter\b'),
        RegExp(r'[^a-zA-Z]AnkiDeckAssembler\b'),
        RegExp(r'[^a-zA-Z]LegacyAnkiImportExecutor\b'),
        RegExp(r'[^a-zA-Z]AnkiCardAdapter\b'),
        RegExp(r'[^a-zA-Z]LegacyAnkiImportFlow\b'),
      ];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        // Allow doc comments mentioning the retired classes.
        final withoutComments = text
            .replaceAll(RegExp(r'//.*'), '')
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
        for (final needle in needles) {
          if (needle.hasMatch(withoutComments)) {
            violations.add('${entity.path} matches ${needle.pattern}');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('C4 collapsed per-capability dart-defines and gray cohort', () {
      final flags = File(
        'lib/application/anki_official/official_anki_feature_flags.dart',
      ).readAsStringSync();
      expect(RegExp(r'bool\.fromEnvironment\(').allMatches(flags).length, 2);
      for (final dead in const [
        'TURNA_OFFICIAL_ANKI_ENGINE',
        'TURNA_OFFICIAL_ANKI_IMPORT',
        'TURNA_OFFICIAL_ANKI_CATALOG',
        'TURNA_OFFICIAL_ANKI_RUNTIME',
        'TURNA_OFFICIAL_ANKI_PLATFORM',
        'TURNA_OFFICIAL_ANKI_RENDERER',
        'TURNA_OFFICIAL_ANKI_PROJECTION',
        'TURNA_OFFICIAL_ANKI_COURSE_ENTRY',
        'TURNA_OFFICIAL_ANKI_SCHEDULER',
        'TURNA_OFFICIAL_ANKI_OFFICIAL_FIRST_IMPORT',
        'TURNA_OFFICIAL_ANKI_GRAY_COHORT',
        'TURNA_OFFICIAL_ANKI_MIGRATION_PILOT',
        'TURNA_OFFICIAL_ANKI_DIAGNOSTICS',
        'TURNA_OFFICIAL_ANKI_LEGACY_MIRROR',
      ]) {
        expect(
          flags.contains("'$dead'"),
          isFalse,
          reason: 'production no longer reads $dead',
        );
      }
      expect(
        File(
          'lib/application/anki_official/migration/official_anki_gray_config.dart',
        ).existsSync(),
        isFalse,
      );
      final launcher = File(
        'lib/application/anki_official/review/formal_review_launcher.dart',
      ).readAsStringSync();
      expect(launcher.contains('officialCapable'), isFalse);
      expect(launcher.contains('schedulerRuntimeAvailable'), isTrue);
      // Step 6: the orchestrator (already an empty hook after doc 39) is
      // fully deleted; its owner decisions live in the v2 commit chain.
      expect(
        File(
          'lib/application/anki_official/import/unified_anki_import_orchestrator.dart',
        ).existsSync(),
        isFalse,
      );
    });

    test('dead dual-policy and unused user migration saga are gone', () {
      expect(
        File(
          'lib/application/anki_official/import/official_first_import_policy.dart',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          'lib/application/anki_official/migration/official_anki_user_migration_saga.dart',
        ).existsSync(),
        isFalse,
      );
    });

    // Doc 35 L0 — orphaned unification infrastructure must stay deleted.
    test('orphaned unification infrastructure stays deleted (doc 35 L0)', () {
      for (final path in const [
        'lib/application/anki/unification/in_memory_anki_unification_store.dart',
        'lib/application/anki/anki_unification_migration.dart',
        'lib/domain/anki/repositories.dart',
        'lib/domain/anki/review_queue_snapshot.dart',
        'lib/domain/anki/course_card_placement.dart',
        'lib/application/anki/anki_media_url_resolver.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: '$path was revived');
      }
      expect(
        Directory('lib/application/anki/unification').existsSync(),
        isFalse,
        reason: 'the unification store directory was revived',
      );
      // Doc 35 L3 boundary inversion: the retired mixed directory is gone;
      // its survivors live in application/study_session, application/
      // anki_import and application/anki_official.
      expect(
        Directory('lib/application/anki').existsSync(),
        isFalse,
        reason: 'lib/application/anki must stay empty after doc 35 L3',
      );
    });

    // Doc 35 L2 — the review-side replica layer must stay deleted.
    test('legacy review layer stays deleted (doc 35 L2)', () {
      for (final path in const [
        'lib/application/anki/anki_review_assembler.dart',
        'lib/application/anki/anki_canonical_card_loader.dart',
        'lib/application/anki/anki_card_html_renderer.dart',
        'lib/application/anki/anki_template_renderer.dart',
        'lib/application/anki/anki_type_answer.dart',
        'lib/application/anki/anki_media_reference_extractor.dart',
        'lib/application/anki/anki_models.dart',
        'lib/views/lesson/components/interactions/anki_html_card_renderer.dart',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: '$path was revived');
      }
      final violations = <String>[];
      final needles = [
        RegExp(r'[^a-zA-Z]AnkiReviewAssembler\b'),
        RegExp(r'[^a-zA-Z]TurnaStudyLedger\b'),
      ];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        final withoutComments = text
            .replaceAll(RegExp(r'//.*'), '')
            .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
        for (final needle in needles) {
          if (needle.hasMatch(withoutComments)) {
            violations.add('${entity.path} matches ${needle.pattern}');
          }
        }
        if (RegExp(r'\bensureWord\s*\(').hasMatch(withoutComments)) {
          violations.add('${entity.path} calls ensureWord');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));

      // The session page must not re-wire the retired Legacy runtime.
      final sessionPage = File('lib/views/anki/anki_review_session_page.dart')
          .readAsStringSync();
      expect(
        sessionPage.contains('package:turna/application/srs_provider.dart'),
        isFalse,
        reason: 'session page must not import SrsProvider',
      );
      expect(
        sessionPage.contains('package:turna/data/anki_note_dao.dart'),
        isFalse,
        reason: 'session page must not import AnkiNoteDao',
      );
    });

    test('anki_official application layer does not import Legacy writers or views',
        () {
      const forbidden = [
        "package:turna/application/anki/anki_importer.dart",
        "package:turna/application/anki/anki_deck_assembler.dart",
        "package:turna/views/anki/",
      ];
      final violations = <String>[];
      final dir = Directory('lib/application/anki_official');
      expect(dir.existsSync(), isTrue);
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        final text = entity.readAsStringSync();
        for (final needle in forbidden) {
          if (text.contains(needle)) {
            violations.add('$path imports $needle');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('official owners do not call SrsProvider.ensureWord/updateReview', () {
      final violations = <String>[];
      final dir = Directory('lib/application/anki_official');
      expect(dir.existsSync(), isTrue);
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('SrsProvider') &&
            (text.contains('.ensureWord') || text.contains('.updateReview'))) {
          violations.add(entity.path);
        }
        if (RegExp(r'\bensureWord\s*\(').hasMatch(text) ||
            RegExp(r'\bupdateReview\s*\(').hasMatch(text)) {
          // Allow comments / docs mentioning the forbidden API.
          final withoutComments = text
              .replaceAll(RegExp(r'//.*'), '')
              .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
          if (RegExp(r'\bensureWord\s*\(').hasMatch(withoutComments) ||
              RegExp(r'\bupdateReview\s*\(').hasMatch(withoutComments)) {
            violations.add('${entity.path} calls ensureWord/updateReview');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });


    // ── Maintainability plan (Wave 1/3/4) guards ─────────────────────
    test('formal-due has one writer: no compatibility facade resurrection',
        () {
      expect(
        File(
          'lib/application/anki_official/engine/official_anki_home_due.dart',
        ).existsSync(),
        isFalse,
        reason: 'the OfficialAnkiHomeDue facade was retired (Wave 1 §7.6)',
      );
      final violations = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (RegExp(r'OfficialAnkiHomeDue\b')
            .hasMatch(entity.readAsStringSync())) {
          violations.add(entity.path);
        }
      }
      expect(violations, isEmpty, reason: violations.join(', '));
    });

    test('views never mutate the formal-due repository', () {
      final violations = <String>[];
      for (final entity in Directory('lib/views').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('.mutateSource(') ||
            text.contains('OfficialFormalDueUpdate(') ||
            text.contains('.markUnavailable(')) {
          violations.add(entity.path);
        }
      }
      expect(violations, isEmpty, reason: violations.join(', '));
    });

    test('lib contains no synthetic official-all source id (Wave 3)', () {
      final violations = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('official-all')) {
          violations.add(entity.path);
        }
      }
      expect(violations, isEmpty, reason: violations.join(', '));
      expect(
        File('lib/application/anki_official/review/formal_review_launcher.dart')
            .readAsStringSync()
            .contains('OfficialReviewAllPlan'),
        isFalse,
        reason: 'OfficialReviewAllPlan was deleted with the aggregate model',
      );
    });

    test('production loader rejects empty source ids (Wave 3 §9.2)', () {
      final loader = File(
        'lib/application/anki_official/review/official_formal_review_production_loader.dart',
      ).readAsStringSync();
      expect(loader.contains('importId.isEmpty'), isTrue);
      expect(
        loader.substring(loader.indexOf('importId.isEmpty') - 200,
                loader.indexOf('importId.isEmpty') + 200)
            .contains('ArgumentError'),
        isTrue,
        reason: 'empty sourceId must throw, not fall back to an aggregate',
      );
    });

    test('import wizard respects the size and dependency gates (Wave 4 §10.8)',
        () {
      int lineCount(String path) =>
          File(path).readAsStringSync().split('\n').length;

      expect(lineCount('lib/views/anki/anki_import_screen.dart'),
          lessThanOrEqualTo(700),
          reason: 'import screen must stay a shell');
      for (final step in const [
        'lib/views/anki/import_wizard/official_anki_import_preview.dart',
        'lib/views/anki/import_wizard/anki_import_done_step.dart',
      ]) {
        expect(lineCount(step), lessThanOrEqualTo(500), reason: step);
      }
      expect(
        lineCount('lib/application/anki_import/anki_import_controller.dart'),
        lessThanOrEqualTo(600),
        reason: 'controller must stay lean (helpers live in view_helpers.dart)',
      );
      expect(
        File('lib/application/anki_import/official_first_anki_import_flow.dart')
            .existsSync(),
        isFalse,
        reason: 'doc 40 P5.6 inlined OfficialFirstAnkiImportFlow into the controller',
      );

      final screen =
          File('lib/views/anki/anki_import_screen.dart').readAsStringSync();
      expect(screen.contains("package:turna/data/"), isFalse,
          reason: 'the page must not import DAOs');
      expect(screen.contains('CourseDatabase'), isFalse);
      expect(screen.contains('getIt<'), isFalse,
          reason: 'the page must not assemble business dependencies');
      expect(screen.contains('LegacyAnkiImportExecutor'), isFalse);
      expect(screen.contains('.importThenPreview('), isFalse);
      expect(screen.contains('projectAndPublish'), isFalse);
    });

    test('dead feature-flag fields and empty orchestrator hook stay deleted', () {
      final flags = File(
        'lib/application/anki_official/official_anki_feature_flags.dart',
      ).readAsStringSync();
      expect(flags.contains('legacyMirror'), isFalse);
      expect(
        RegExp(r'\bthis\.diagnostics\b').hasMatch(flags),
        isFalse,
        reason: 'OfficialAnkiFeatureFlags.diagnostics was unused',
      );
      // Step 6: the empty orchestrator hook is fully deleted.
      expect(
        File(
          'lib/application/anki_official/import/unified_anki_import_orchestrator.dart',
        ).existsSync(),
        isFalse,
        reason: 'the retired v1 publish orchestrator must stay deleted',
      );
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('TURNA_OFFICIAL_ANKI_LEGACY_MIRROR')) {
          fail('${entity.path} revived TURNA_OFFICIAL_ANKI_LEGACY_MIRROR');
        }
      }
    });

    test('doc 42 P4 live-first import is retired', () {
      final first = File(
        'lib/application/anki_official/import/official_anki_official_first_service.dart',
      ).readAsStringSync();
      expect(first.contains('importOfficialOrNull'), isFalse);
      expect(first.contains('facade.importFile'), isFalse);
      final orch = File(
        'lib/application/anki_official/import/official_anki_import_orchestrator.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'\b(importFile|_importFile)\s*\(').hasMatch(orch),
        isFalse,
        reason: 'orchestrator must not keep live-first importFile',
      );
      expect(orch.contains('createBackup'), isFalse);
    });

    test('unsupported platform never selects Legacy writer (execution plan)', () {
      // Behavior is asserted in anki_import_execution_plan_test.dart
      // ("non-android is unsupported" / platform matrix). Keep a pointer so
      // W9 §13.3 CI inventory does not forget that surface.
      final planTest = File(
        'test/application/anki_official/anki_import_execution_plan_test.dart',
      );
      expect(planTest.existsSync(), isTrue);
      final text = planTest.readAsStringSync();
      expect(text.contains('unsupported'), isTrue);
      expect(text.contains('writesLegacyNoteStore'), isTrue);
      expect(text.contains("platform: 'ohos'") || text.contains('ohos'), isTrue);
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
