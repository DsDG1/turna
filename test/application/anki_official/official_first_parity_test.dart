// P5F-42: dual-pipeline parity harness. For every frozen p5c fixture the
// legacy Dart pipeline (parse + assemble) and the official-first pipeline
// (catalog + FakeOfficialAnkiEngine + projection service) each import the
// same package into their own in-memory course DB; the observable outputs
// are then diffed against the allowlist in
// test/fixtures/anki_official/parity_allowlist.json.
//
// The fake engine mints sequential card ids, so card-id-level equality is
// host-job territory (real rslib preserves package ids); here we assert
// counts, cardinality, and the by-design deltas.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';

import '../../helpers/in_memory_course_db.dart';

const _fixtures = [
  'test/application/anki_official/fixtures/p5c/classic-basic.apkg',
  'test/application/anki_official/fixtures/p5c/basic-cloze.apkg',
];

Future<int> _count(CourseDatabase db, String sql) async {
  final rows = await db.customSelect(sql).get();
  return rows.isEmpty ? 0 : rows.first.read<int>('n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  test('parity allowlist is valid json with known entries', () {
    final allowlist = jsonDecode(
        File('test/fixtures/anki_official/parity_allowlist.json')
            .readAsStringSync()) as Map<String, dynamic>;
    expect(allowlist['schemaVersion'], 1);
    final entries = (allowlist['entries'] as List)
        .map((e) => (e as Map)['id'] as String)
        .toSet();
    expect(
        entries,
        containsAll(<String>[
          'tree-shape',
          'one-kind-per-card',
          'vocabulary-subset',
          'no-legacy-bookkeeping',
          'card-id-parity-scope',
        ]));
  });

  for (final fixture in _fixtures) {
    test('p5f_parity $fixture', () async {
      // ── legacy pipeline ──────────────────────────────────────────────
      final legacyDb = CourseDatabase(NativeDatabase.memory());
      addTearDown(legacyDb.close);
      final legacyRepo = CourseRepository(legacyDb);
      AnkiNoteDao(legacyDb);
      final collection = await AnkiImporter().parse(fixture);
      final summary = await AnkiDeckAssembler().assemble(
        collection: collection,
        importId: 'parity-legacy',
        repo: legacyRepo,
        noteDao: AnkiNoteDao(legacyDb),
        smartGrouping: true,
      );
      final legacySections = await _count(legacyDb,
          "SELECT COUNT(*) AS n FROM sections WHERE id LIKE 'anki-parity-legacy-%'");

      // ── official-first pipeline ──────────────────────────────────────
      final officialDb = CourseDatabase(NativeDatabase.memory());
      addTearDown(officialDb.close);
      final catalog = OfficialAnkiDatabase.memory();
      addTearDown(catalog.close);
      const sourceId = 'src-parity';
      OfficialAnkiSourceDao(catalog).upsertSource(
        sourceId: sourceId,
        profileId: 'profile-default-01',
        sourceHash: collection.sourceHash,
        sourceSize: 1,
        displayName: 'parity',
        state: 'active',
        backendCommit: 'test',
        nowMillis: 1,
      );
      // The fake engine mints sequential card/note ids (1..n); the catalog
      // descriptors must share that id space or the projection scan
      // fail-closes with PROJECTION_SOURCE_CHANGED. Real-id parity is a
      // host-job concern (allowlist: card-id-parity-scope).
      OfficialAnkiSourceDao(catalog).replaceCards(
        sourceId: sourceId,
        cards: [
          for (var i = 1; i <= collection.cards.length; i++)
            OfficialAnkiCardDescriptor(
              cardId: i,
              noteId: i,
              deckId: 1,
              templateOrd: 0,
              noteGuid: 'guid-$i',
            ),
        ],
      );
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(
        packagePath: fixture,
        notes: collection.notes.length,
        cards: collection.cards.length,
      );
      final service = OfficialAnkiCourseProjectionService(
        engine: engine,
        catalog: catalog,
        course: officialDb,
        sourceId: sourceId,
        profileId: 'profile-default-01',
        flags: const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
        ),
      );
      // Mirror the wizard: proceeding auto-confirms suggested mappings.
      for (final schema in await engine.getProjectionSchemas()) {
        service.confirmMapping(
          schema: schema,
          suggestion: OfficialAnkiProjectionMapper().suggest(schema: schema),
        );
      }
      final result = await service.projectSource();
      expect(result.failed, isFalse, reason: result.errorCode ?? '');
      expect(result.needsMapping, isFalse);

      final indexCount = await _count(officialDb,
          'SELECT COUNT(*) AS n FROM official_anki_projection_index');
      final officialSections = await _count(officialDb,
          "SELECT COUNT(*) AS n FROM sections WHERE id LIKE 'official-anki-%'");
      final officialVocab =
          await _count(officialDb, 'SELECT COUNT(*) AS n FROM vocabulary');

      // ── diffs (outside the allowlist must be equal) ─────────────────
      // Card-count parity: every parsed card appears in both pipelines.
      expect(indexCount, collection.cards.length,
          reason: 'official projection covers every parsed card');
      expect(summary.cardCount, collection.cards.length,
          reason: 'legacy assembler covers every parsed card');

      // Both pipelines produce a navigable course tree (shape itself is an
      // allowlisted difference — grouping heuristics differ).
      expect(legacySections, greaterThan(0));
      expect(officialSections, greaterThan(0));

      // Vocabulary parity (allowlist: vocabulary-subset): counts may differ
      // in either direction — structured decks get a subset, cloze decks may
      // surface a term/translation pair the legacy adapter never
      // materialized. The hard invariant: at most one row per card.
      expect(officialVocab, lessThanOrEqualTo(collection.cards.length));

      // By design (allowlist: no-legacy-bookkeeping): the official path
      // writes no legacy import rows and no Turna SRS states.
      expect(
        await _count(officialDb, 'SELECT COUNT(*) AS n FROM anki_imports'),
        0,
      );
      expect(
        await _count(officialDb, 'SELECT COUNT(*) AS n FROM srs_states'),
        0,
      );

      // One presentation kind per card (allowlist: one-kind-per-card).
      final kindsPerCard = await officialDb
          .customSelect(
            'SELECT card_id, COUNT(DISTINCT projection_kind) AS k '
            'FROM official_anki_projection_index GROUP BY card_id '
            'HAVING k > 1',
          )
          .get();
      expect(kindsPerCard, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
