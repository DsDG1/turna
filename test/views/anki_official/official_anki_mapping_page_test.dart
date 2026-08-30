// Plain-language mapping page tests: the wizard must surface Chinese role
// and status labels instead of raw enum names (`prompt`, `auto`,
// `confidence=0.95`), keep its action keys, and still deliver the edited
// suggestion through onConfirm.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/views/anki_official/official_anki_mapping_page.dart';

OfficialAnkiMappingSuggestion _suggestion() =>
    const OfficialAnkiMappingSuggestion(
      status: OfficialAnkiMappingStatus.auto,
      archetype: 'basicPair',
      recognitionConfidence: 0.9,
      candidates: [
        OfficialAnkiFieldCandidate(
          role: FieldRole.prompt,
          fieldIndex: 0,
          fieldName: 'Front',
          confidence: 0.95,
          evidence: ['rule', 'fieldShape'],
        ),
        OfficialAnkiFieldCandidate(
          role: FieldRole.response,
          fieldIndex: 1,
          fieldName: 'Back',
          confidence: 0.9,
          evidence: ['rule'],
        ),
      ],
    );

OfficialAnkiProjectionSchema _schema() => OfficialAnkiProjectionSchema(
      notetypeId: 7,
      name: 'Basic',
      kind: 'normal',
      fieldNames: const ['Front', 'Back', 'Audio'],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp',
      samples: const [
        OfficialAnkiProjectionSample(
          noteId: 42,
          fields: ['merhaba', '你好', 'merhaba.mp3'],
        ),
      ],
    );

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows plain Chinese labels, hides raw enums and confidence',
      (tester) async {
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Basic',
      suggestion: _suggestion(),
      schema: _schema(),
      affectedCardCount: 12,
    )));

    expect(find.text('正面'), findsWidgets);
    expect(find.text('背面'), findsWidgets);
    expect(find.text('这样显示正确吗？'), findsOneWidget);
    expect(find.textContaining('已按卡片结构识别'), findsOneWidget);
    expect(find.textContaining('共 12 张'), findsOneWidget);
    expect(find.text('merhaba'), findsOneWidget);

    // Raw technical vocabulary must not leak into the simplified page.
    expect(find.textContaining('targetText'), findsNothing);
    expect(find.textContaining('basicPair'), findsNothing);
    expect(find.textContaining('autoCandidate'), findsNothing);
    expect(find.textContaining('confidence'), findsNothing);
    expect(find.textContaining('0.95'), findsNothing);
    expect(find.text('发音'), findsNothing,
        reason: 'optional field roles stay collapsed by default');
  });

  testWidgets('save delivers the current suggestion', (tester) async {
    OfficialAnkiMappingSuggestion? confirmed;
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Basic',
      suggestion: _suggestion(),
      schema: _schema(),
      onConfirm: (next) => confirmed = next,
    )));

    final save = find.byKey(const Key('mapping-save'));
    await tester.scrollUntilVisible(save, 200);
    await tester.tap(save);
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(
        confirmed!.role(FieldRole.prompt)?.fieldName, 'Front');
  });

  testWidgets('reassigning a role through the dropdown notifies onChanged',
      (tester) async {
    OfficialAnkiMappingSuggestion? changed;
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Basic',
      suggestion: _suggestion(),
      schema: _schema(),
      onChanged: (next) => changed = next,
    )));

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mapping-more-fields')));
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const Key('mapping-role-pronunciation'));
    await tester.scrollUntilVisible(dropdown, 200);
    tester.widget<DropdownButton<int>>(dropdown).onChanged?.call(2);
    await tester.pump();

    expect(changed, isNotNull);
    expect(
      changed!.role(FieldRole.pronunciation)?.fieldIndex,
      2,
    );
  });

  testWidgets('swapping question and answer updates the suggestion',
      (tester) async {
    OfficialAnkiMappingSuggestion? changed;
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Basic',
      suggestion: _suggestion(),
      schema: _schema(),
      onChanged: (next) => changed = next,
    )));

    await tester.tap(find.byKey(const Key('mapping-swap')));
    await tester.pump();

    expect(changed, isNotNull);
    expect(
      changed!.role(FieldRole.prompt)?.fieldName,
      'Back',
    );
    expect(
      changed!.role(FieldRole.response)?.fieldName,
      'Front',
    );
  });

  testWidgets(
      'missing question and answer still lets save enter pick-front',
      (tester) async {
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Unknown',
      suggestion: const OfficialAnkiMappingSuggestion(
        status: OfficialAnkiMappingStatus.review,
        candidates: [],
      ),
      schema: _schema(),
    )));

    expect(find.textContaining('看一下样卡'), findsWidgets);
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('mapping-save')),
    );
    expect(save.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('mapping-save')));
    await tester.pump();
    expect(find.byKey(const Key('mapping-front-choice-0')), findsOneWidget);
    expect(find.byKey(const Key('mapping-front-choice-1')), findsOneWidget);
  });

  testWidgets('advisory status keeps confirmation available', (tester) async {
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Basic',
      suggestion: _suggestion().copyWith(
        status: OfficialAnkiMappingStatus.review,
      ),
      schema: _schema(),
    )));

    expect(find.textContaining('建议看一眼样卡'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('mapping-save')),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets('exercise presets default to auto and select through chips',
      (tester) async {
    OfficialAnkiMappingSuggestion? confirmed;
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Basic',
      suggestion: _suggestion(),
      schema: _schema(),
      onConfirm: (next) => confirmed = next,
    )));

    // The default suggestion kind list reads as the 自动 preset.
    final auto =
        tester.widget<ChoiceChip>(find.byKey(const Key('exercise-preset-auto')));
    expect(auto.selected, isTrue);

    final choiceChip = find.byKey(const Key('exercise-preset-choice'));
    await tester.scrollUntilVisible(choiceChip, 200);
    await tester.tap(choiceChip);
    await tester.pump();

    final save = find.byKey(const Key('mapping-save'));
    await tester.scrollUntilVisible(save, 200);
    await tester.tap(save);
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.enabledKinds, contains('multipleChoice'));
    expect(confirmed!.enabledKinds, isNot(contains('listenPick')));
    // Field roles are untouched by the exercise choice.
    expect(
        confirmed!.role(FieldRole.prompt)?.fieldName, 'Front');
  });

  testWidgets(
    'P0 S-d: save is tappable before picking front, then pops confirmed',
    (tester) async {
      OfficialAnkiMappingSuggestion? confirmed;
      var mappingPopped = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => OfficialAnkiMappingPage(
                    notetypeName: 'Unknown',
                    suggestion: const OfficialAnkiMappingSuggestion(
                      status: OfficialAnkiMappingStatus.review,
                      candidates: [],
                    ),
                    schema: _schema(),
                    onConfirm: (next) => confirmed = next,
                  ),
                ),
              );
              mappingPopped = true;
            },
            child: const Text('open-mapping'),
          ),
        ),
      ));
      await tester.tap(find.text('open-mapping'));
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(
        find.byKey(const Key('mapping-save')),
      );
      expect(
        save.onPressed,
        isNotNull,
        reason: 'blocking mapping must still let the user tap save (enters pick-front)',
      );

      await tester.tap(find.byKey(const Key('mapping-save')));
      await tester.pump();
      expect(find.byKey(const Key('mapping-front-choice-0')), findsOneWidget);
      expect(find.byKey(const Key('mapping-front-choice-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mapping-front-choice-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('mapping-save')));
      await tester.pumpAndSettle();

      expect(mappingPopped, isTrue);
      expect(find.byType(OfficialAnkiMappingPage), findsNothing);
      expect(confirmed, isNotNull);
      expect(confirmed!.role(FieldRole.prompt), isNotNull);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Text(
            confirmed != null ? '已确认' : '未确认',
            key: const Key('preview-notetype-status'),
          ),
        ),
      ));
      expect(find.text('已确认'), findsOneWidget);
    },
  );

  testWidgets('cloze schema surfaces the fill-blank note', (tester) async {
    await tester.pumpWidget(_host(OfficialAnkiMappingPage(
      notetypeName: 'Cloze',
      suggestion: _suggestion(),
      schema: OfficialAnkiProjectionSchema(
        notetypeId: 8,
        name: 'Cloze',
        kind: 'cloze',
        fieldNames: const ['Text', 'Extra'],
        templateNames: const ['Cloze'],
        schemaFingerprint: 'fp2',
        samples: const [
          OfficialAnkiProjectionSample(
            noteId: 43,
            fields: ['{{c1::merhaba}} means hello', ''],
          ),
        ],
      ),
      affectedCardCount: 3,
    )));

    expect(find.textContaining('挖空'), findsOneWidget);
  });
}
