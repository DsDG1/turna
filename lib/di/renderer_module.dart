// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/listen_only_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_mcq_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_short_answer_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_true_false_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reorder_sentence_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/show_word_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/translate_sentence_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/type_the_word_renderer.dart';

/// Plugin-style DI for [InteractionRenderer]s.
///
/// This is the Dart / GetIt analogue of a Hilt `@IntoSet` multibinding. Each
/// concrete renderer is registered as an `@injectable` factory; this module
/// collects them all into a single `Set<InteractionRenderer>` that the
/// lesson screen dispatcher uses to look up a renderer by
/// `interaction.runtimeType`.
///
/// Adding a new [Interaction] type:
///   1. Create `FooBarRenderer extends InteractionRenderer` with `@injectable`.
///   2. (If the type auto-advances on submit, override `bool get autoAdvance
///      => true;` — the screen reads this instead of special-casing the
///      type.)
///   3. Add a parameter for it here and add it to the returned set.
///   4. Re-run `dart run build_runner build`.
@module
abstract class RendererModule {
  @lazySingleton
  Set<InteractionRenderer> renderers(
    ShowWordRenderer showWord,
    MultipleChoiceRenderer multipleChoice,
    FillBlankRenderer fillBlank,
    TranslateSentenceRenderer translateSentence,
    ListenAndPickRenderer listenAndPick,
    TypeTheWordRenderer typeTheWord,
    ListenOnlyRenderer listenOnly,
    ReorderSentenceRenderer reorderSentence,
    ReadingMcqRenderer readingMcq,
    ReadingTrueFalseRenderer readingTrueFalse,
    ReadingShortAnswerRenderer readingShortAnswer,
  ) =>
      {
        showWord,
        multipleChoice,
        fillBlank,
        translateSentence,
        listenAndPick,
        typeTheWord,
        listenOnly,
        reorderSentence,
        readingMcq,
        readingTrueFalse,
        readingShortAnswer,
      };
}