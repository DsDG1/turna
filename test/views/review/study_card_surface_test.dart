import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';
import 'package:turna/views/review/components/flutter_course_card_body.dart';
import 'package:turna/views/review/components/study_card_surface.dart';

void main() {
  testWidgets('structured MCQ uses the course renderer instead of flip text',
      (tester) async {
    const interaction = Interaction.multipleChoice(
      id: 'mc-1',
      prompt: 'Choose the target',
      options: ['kedi', 'köpek', 'kuş'],
      correctIndex: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyCardSurface(
            content: const StandardCourseCardContent(
              frontText: 'kedi',
              backText: 'cat',
              interaction: interaction,
            ),
            isRevealed: false,
            onReveal: _noop,
            renderers: {
              MultipleChoiceRenderer(),
              MultiSelectRenderer(),
              FillBlankRenderer(),
              ListenAndPickRenderer(),
              TypeTheWordRenderer(),
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Choose the target'), findsOneWidget);
    expect(find.text('kedi'), findsOneWidget);
    expect(find.text('köpek'), findsOneWidget);
    expect(find.byType(FlutterCourseCardBody), findsNothing);
  });

  testWidgets('flip content still uses the shared flip surface', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudyCardSurface(
            content: StandardCourseCardContent(
              frontText: 'merhaba',
              backText: 'hello',
            ),
            isRevealed: false,
            onReveal: _noop,
          ),
        ),
      ),
    );
    expect(find.byType(FlutterCourseCardBody), findsOneWidget);
    expect(find.text('merhaba'), findsOneWidget);
    expect(find.text('hello'), findsNothing);
  });
}

void _noop() {}
