import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';

void main() {
  test('skip clears needsMapping when that notetype was the only blocker', () {
    final schema = OfficialAnkiProjectionSchema(
      notetypeId: 7,
      name: 'Unknown',
      kind: 'normal',
      fieldNames: const ['Front', 'Back'],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp',
    );
    final preview = OfficialAnkiImportPreviewModel(
      plan: const AnkiImportExecutionPlan(
        productMode: AnkiProductMode.officialAndroid,
        kind: AnkiImportExecutionKind.officialFirst,
        owner: AnkiImportOwner.official,
        platform: 'test',
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: true,
        reason: 'test',
      ),
      filePath: 'x.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 1,
      noteCount: 1,
      decks: const [],
      schemas: [schema],
      suggestions: const {
        7: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.review,
          candidates: [],
        ),
      },
      service: _StubService(),
      needsMapping: true,
    );

    expect(officialRecognitionTriage(preview, schema).blocking, isTrue);
    preview.skippedNotetypes.add(7);
    refreshOfficialPreviewNeedsMapping(preview);
    expect(preview.needsMapping, isFalse);
    expect(officialRecognitionTriage(preview, schema).skipped, isTrue);
  });
}

class _StubService implements OfficialAnkiCourseProjectionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
