// Widget tests for the question-type chip UI: the recognition row exposes
// one tap per plain question type, and the mapping editor dialog maps a
// 填空题 tap to cloze or type-the-answer based on the notetype's markers.

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/import_wizard/question_type.dart';
import 'package:turna/views/anki/import_wizard/anki_notetype_mapping_editor.dart';

AnkiNotetype _notetype() => const AnkiNotetype(
      id: 5,
      name: 'Basic (and reversed)',
      fieldNames: ['Front', 'Back'],
      templateNames: ['Card 1', 'Card 2'],
    );

AnkiNote _note() => const AnkiNote(
      id: 42,
      mid: 5,
      fields: ['merhaba', '你好'],
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<Future<NotetypeMapping?>> _openEditor(
  WidgetTester tester, {
  required bool hasClozeMarkers,
  NotetypeMapping? initial,
}) async {
  late Future<NotetypeMapping?> popped;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            popped = showDialog<NotetypeMapping>(
              context: context,
              builder: (_) => NotetypeMappingEditor(
                notetype: _notetype(),
                note: _note(),
                initialMapping: initial,
                hasClozeMarkers: hasClozeMarkers,
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

Future<NotetypeMapping> _confirm(WidgetTester tester, Future<NotetypeMapping?> popped) async {
  await tester.tap(find.byKey(const Key('mapping-edit-confirm')));
  await tester.pumpAndSettle();
  final mapping = await popped;
  expect(mapping, isNotNull);
  return mapping!;
}

void main() {
  testWidgets('row renders one chip per question type and reports taps',
      (tester) async {
    final selected = <UserQuestionType>[];
    await tester.pumpWidget(_host(NotetypeMappingRow(
      notetype: _notetype(),
      mapping: const NotetypeMapping(type: NotetypeMappingType.wordEntry),
      recognition: const CardRecognitionResult(
        mapping: NotetypeMapping(type: NotetypeMappingType.wordEntry),
        confidence: 0.8,
        source: CardRecognitionSource.rule,
        evidence: 'rule',
      ),
      attention: ImportRecognitionAttention.recognized,
      cardCount: 12,
      onTypeSelected: selected.add,
      onEdit: () {},
    )));

    expect(find.byKey(const Key('question-type-choice')), findsOneWidget);
    expect(find.byKey(const Key('question-type-fillBlank')), findsOneWidget);
    expect(find.byKey(const Key('question-type-listen')), findsOneWidget);
    expect(find.byKey(const Key('question-type-word')), findsOneWidget);
    expect(find.byKey(const Key('question-type-sentence')), findsOneWidget);
    expect(find.byKey(const Key('question-type-flip')), findsOneWidget);

    // Selected chip from an automatic verdict carries the 自动 badge.
    expect(find.text('单词卡 · 自动'), findsOneWidget);
    expect(find.text('12 张卡片'), findsOneWidget);
    expect(find.textContaining('牌组里叫'), findsOneWidget);

    await tester.tap(find.byKey(const Key('question-type-choice')));
    expect(selected, [UserQuestionType.choice]);
  });

  testWidgets('editor maps 填空题 to cloze when markers exist', (tester) async {
    final popped = await _openEditor(
      tester,
      hasClozeMarkers: true,
      initial: const NotetypeMapping(type: NotetypeMappingType.wordEntry),
    );
    await tester.tap(find.byKey(const Key('question-type-fillBlank')));
    await tester.pump();
    final mapping = await _confirm(tester, popped);
    expect(mapping.type, NotetypeMappingType.cloze);
  });

  testWidgets('editor maps 填空题 to type-the-answer without markers',
      (tester) async {
    final popped = await _openEditor(
      tester,
      hasClozeMarkers: false,
      initial: const NotetypeMapping(type: NotetypeMappingType.wordEntry),
    );
    await tester.tap(find.byKey(const Key('question-type-fillBlank')));
    await tester.pump();
    final mapping = await _confirm(tester, popped);
    expect(mapping.type, NotetypeMappingType.fillBlank);
  });

  testWidgets('editor keeps field indexes when switching type', (tester) async {
    final popped = await _openEditor(
      tester,
      hasClozeMarkers: false,
      initial: const NotetypeMapping(
        type: NotetypeMappingType.wordEntry,
        frontFieldIndex: 0,
        backFieldIndex: 1,
      ),
    );
    await tester.tap(find.byKey(const Key('question-type-choice')));
    await tester.pump();
    final mapping = await _confirm(tester, popped);
    expect(mapping.type, NotetypeMappingType.multipleChoice);
    expect(mapping.frontFieldIndex, 0);
    expect(mapping.backFieldIndex, 1);
  });
}
