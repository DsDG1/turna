// Doc 42 §10.1 P0 failing gate (S-c). File-backed catalog SQLite.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

class _CollectionWithForeignNotetype extends FakeOfficialAnkiEngine {
  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) async {
    final inScope = await super.getProjectionSchemas(
      notetypeIds: notetypeIds,
      includeSamples: includeSamples,
      sampleLimit: sampleLimit,
    );
    const foreign = OfficialAnkiProjectionSchema(
      notetypeId: 99,
      name: 'Unrelated leftover',
      kind: 'normal',
      fieldNames: ['X', 'Y'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'foreign-unconfirmed',
      samples: [
        OfficialAnkiProjectionSample(noteId: 900, fields: ['aaa', 'bbb']),
      ],
    );
    if (notetypeIds.isNotEmpty) {
      return [
        ...inScope,
        if (notetypeIds.contains(99)) foreign,
      ];
    }
    return [...inScope, foreign];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  test(
    'P0 S-c: source-scoped projectSource ignores foreign unconfirmed notetypes',
    () async {
      final root = Directory.systemTemp.createTempSync('turna-p0-proj-');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      final catalog = OfficialAnkiDatabase.file(
        p.join(root.path, 'official_catalog.sqlite'),
      );
      addTearDown(catalog.close);
      OfficialAnkiSourceDao(catalog).upsertSource(
        sourceId: 'src1',
        profileId: 'profile-a',
        sourceHash: 'h',
        sourceSize: 1,
        displayName: 'src',
        state: 'active',
        backendCommit: '967aa0d578fc75181e292e95326f9b58698da25c',
        nowMillis: 1,
      );
      OfficialAnkiSourceDao(catalog).replaceCards(
        sourceId: 'src1',
        cards: [
          for (var i = 1; i <= 2; i++)
            OfficialAnkiCardDescriptor(
              cardId: i,
              noteId: i,
              deckId: 1,
              templateOrd: 0,
              noteGuid: 'g$i',
              notetypeId: 1,
            ),
        ],
      );
      final course = CourseDatabase(NativeDatabase.memory());
      addTearDown(course.close);
      final engine = _CollectionWithForeignNotetype();
      engine.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
      final service = OfficialAnkiCourseProjectionService(
        engine: engine,
        catalog: catalog,
        course: course,
        sourceId: 'src1',
        profileId: 'profile-a',
        flags: const OfficialAnkiFeatureFlags(
          engine: true,
          import: true,
          catalogReady: true,
          runtimeCapable: true,
          projection: true,
        ),
      );
      const inScope = OfficialAnkiProjectionSchema(
        notetypeId: 1,
        name: 'Basic',
        kind: 'normal',
        fieldNames: ['Front', 'Back'],
        templateNames: ['Card 1'],
        schemaFingerprint: 'fake-basic',
      );
      service.confirmMapping(
        schema: inScope,
        suggestion: officialAnkiSuggestMapping(inScope, const CardRecognizer()),
      );

      // Doc 42 invariant 5: production must pass the source notetype scope.
      // Until projectSource grows that argument, this is the live entry.
      final result = await service.projectSource(notetypeIds: const [1]);

      expect(result.needsMapping, isFalse);
      expect(result.failed, isFalse);
      expect(result.itemCount, greaterThan(0));
    },
  );
}
