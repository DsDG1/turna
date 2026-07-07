// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:words625/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:words625/views/lesson/components/interactions/reorder_sentence_renderer.dart';
import 'package:words625/views/lesson/components/interactions/show_word_renderer.dart';
import 'package:words625/views/lesson/components/interactions/translate_sentence_renderer.dart';
import 'package:words625/views/lesson/components/interactions/type_the_word_renderer.dart';

/// Plugin-style DI for [InteractionRenderer]s.
///
/// This is the Dart / GetIt analogue of a Hilt `@IntoSet` multibinding. Each
/// concrete renderer is registered as an `@injectable` factory; this module
/// collects them all into a single `Set<InteractionRenderer>` that the
/// [LessonContentScreen] dispatcher uses to look up a renderer by
/// `interaction.runtimeType`.
///
/// Adding a new [Interaction] type:
///   1. Create `FooBarRenderer extends InteractionRenderer` with `@injectable`.
///   2. Add a parameter for it here.
///   3. Add it to the returned set.
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
    ReorderSentenceRenderer reorderSentence,
  ) =>
      {
        showWord,
        multipleChoice,
        fillBlank,
        translateSentence,
        listenAndPick,
        typeTheWord,
        reorderSentence,
      };
}
