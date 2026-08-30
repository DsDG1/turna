import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/views/anki/import_wizard/official_anki_import_preview.dart';

/// Doc 37 §4 — the preview's per-notetype "four-piece": sample card by
/// binding, archetype chip + band, expandable evidence, override entry.
void main() {
  testWidgets('preview shows the four-piece recognition card', (tester) async {
    final controller = _StubController();
    var openedNotetypeId = 0;
    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'x.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 2,
      noteCount: 2,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'Default', level: 1),
      ],
      schemas: [
        OfficialAnkiProjectionSchema(
          notetypeId: 1,
          name: 'Basic',
          kind: 'normal',
          fieldNames: const ['Front', 'Back'],
          templateNames: const ['Card 1'],
          schemaFingerprint: 'fp',
          samples: const [
            OfficialAnkiProjectionSample(
              noteId: 1,
              fields: ['merhaba', '你好'],
            ),
          ],
        ),
      ],
      suggestions: const {
        1: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.review,
          archetype: 'basicPair',
          recognitionConfidence: 0.75,
          candidates: [
            OfficialAnkiFieldCandidate(
              role: FieldRole.prompt,
              fieldIndex: 0,
              fieldName: 'Front',
              confidence: 0.9,
              evidence: ['lexicon:exact (Front)'],
            ),
            OfficialAnkiFieldCandidate(
              role: FieldRole.response,
              fieldIndex: 1,
              fieldName: 'Back',
              confidence: 0.9,
              evidence: ['lexicon:exact (Back)'],
            ),
          ],
        ),
      },
      service: _StubService(),
      showAllRecognition: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OfficialAnkiImportPreview(
          preview: preview,
          controller: controller,
          error: null,
          onOpenMapping: (schema) => openedNotetypeId = schema.notetypeId,
        ),
      ),
    ));

    // 1) archetype chip + confidence band.
    expect(find.byKey(const Key('recognition-chip-1')), findsOneWidget);
    expect(find.textContaining('正反翻面'), findsOneWidget);
    expect(find.textContaining('建议确认'), findsOneWidget);
    // 2) sample preview follows the binding (Front → Back).
    expect(find.byKey(const Key('recognition-sample-1')), findsOneWidget);
    expect(find.textContaining('merhaba'), findsOneWidget);
    // 3) evidence expansion lists the role bindings.
    await tester.tap(find.byKey(const Key('recognition-evidence-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('正面: Front'), findsOneWidget);
    expect(find.textContaining('背面: Back'), findsOneWidget);
    // 4) override entry opens the mapping editor for this notetype.
    await tester.tap(find.byKey(const Key('recognition-chip-1')));
    await tester.pump();
    expect(openedNotetypeId, 1);
  });

  testWidgets('confirmed notetype row shows 已确认', (tester) async {
    final preview = OfficialAnkiImportPreviewModel(
      plan: _plan(),
      filePath: 'x.apkg',
      sourceId: 'src-1',
      sourceHash: 'h',
      cardCount: 2,
      noteCount: 2,
      decks: const [
        OfficialAnkiDeckNode(deckId: 1, name: 'Default', level: 1),
      ],
      schemas: [
        OfficialAnkiProjectionSchema(
          notetypeId: 1,
          name: 'Basic',
          kind: 'normal',
          fieldNames: const ['Front', 'Back'],
          templateNames: const ['Card 1'],
          schemaFingerprint: 'fp',
          samples: const [
            OfficialAnkiProjectionSample(
              noteId: 1,
              fields: ['merhaba', '你好'],
            ),
          ],
        ),
      ],
      suggestions: const {
        1: OfficialAnkiMappingSuggestion(
          status: OfficialAnkiMappingStatus.manual,
          archetype: 'basicPair',
          candidates: [
            OfficialAnkiFieldCandidate(
              role: FieldRole.prompt,
              fieldIndex: 0,
              fieldName: 'Front',
              confidence: 1,
              evidence: ['user'],
            ),
            OfficialAnkiFieldCandidate(
              role: FieldRole.response,
              fieldIndex: 1,
              fieldName: 'Back',
              confidence: 1,
              evidence: ['user'],
            ),
          ],
        ),
      },
      service: _StubService(),
      confirmedNotetypes: {1},
      showAllRecognition: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OfficialAnkiImportPreview(
          preview: preview,
          controller: _StubController(),
          error: null,
          onOpenMapping: (_) {},
        ),
      ),
    ));
    expect(find.text('已确认'), findsWidgets);
  });
}

AnkiImportExecutionPlan _plan() => const AnkiImportExecutionPlan(
      productMode: AnkiProductMode.officialAndroid,
      kind: AnkiImportExecutionKind.officialFirst,
      owner: AnkiImportOwner.official,
      platform: 'test',
      writesLegacyNoteStore: false,
      writesTurnaAnkiSrs: false,
      writesOfficialCollection: true,
      reason: 'test',
    );

class _StubController implements AnkiImportController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubService implements OfficialAnkiCourseProjectionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
