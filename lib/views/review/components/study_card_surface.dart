import 'package:flutter/material.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/anki_card_renderer.dart';
import 'package:turna/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';
import 'package:turna/views/review/components/flutter_course_card_body.dart';
import 'package:turna/views/review/components/official_template_webview_body.dart';

/// Shared card body for learn/review/preview. Structured items reuse the
/// course [InteractionRenderer] set instead of flattening to front/back.
class StudyCardSurface extends StatefulWidget {
  const StudyCardSurface({
    super.key,
    this.presentation,
    this.content,
    required this.isRevealed,
    required this.onReveal,
    this.onSpeak,
    this.onObjectiveResult,
    this.onPresented,
    this.generation = 0,
    this.renderers,
  });

  final CardPresentation? presentation;
  final ReviewContentBodyData? content;
  final bool isRevealed;
  final VoidCallback onReveal;
  final VoidCallback? onSpeak;
  final ValueChanged<bool>? onObjectiveResult;
  final ValueChanged<PresentationReceipt>? onPresented;
  final int generation;
  final Set<InteractionRenderer>? renderers;

  @override
  State<StudyCardSurface> createState() => _StudyCardSurfaceState();
}

class _StudyCardSurfaceState extends State<StudyCardSurface> {
  InteractionState _state = InteractionState.idle;

  @override
  void didUpdateWidget(covariant StudyCardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation) {
      _state = InteractionState.idle;
    }
    _scheduleAck();
  }

  @override
  void initState() {
    super.initState();
    _scheduleAck();
  }

  void _scheduleAck() {
    final presentation = widget.presentation;
    if (presentation == null || widget.onPresented == null) return;
    final side =
        widget.isRevealed || _state.submitted ? PresentationSide.answer : PresentationSide.question;
    final renderer = switch (presentation) {
      StructuredCardPresentation() => PresentationRendererKind.flutterStructured,
      FlipCardPresentation() => PresentationRendererKind.flutterFlip,
      FidelityCardPresentation() => PresentationRendererKind.officialTemplate,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onPresented!(
        PresentationReceipt(
          cardKey: presentation.cardKey,
          generation: widget.generation,
          side: side,
          renderer: renderer,
          presentedAt: DateTime.now(),
        ),
      );
    });
  }

  Set<InteractionRenderer> get _renderers =>
      widget.renderers ??
      {
        AnkiCardRenderer(),
        MultipleChoiceRenderer(),
        MultiSelectRenderer(),
        FillBlankRenderer(),
        ListenAndPickRenderer(),
        TypeTheWordRenderer(),
      };

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    if (presentation is StructuredCardPresentation) {
      return _structured(presentation.interaction);
    }
    if (presentation is FlipCardPresentation) {
      return FlutterCourseCardBody(
        content: StandardCourseCardContent(
          frontText: presentation.frontText,
          frontPronunciation: presentation.pronunciation,
          backText: presentation.backText,
          backNote: presentation.hint,
        ),
        isRevealed: widget.isRevealed,
        onReveal: widget.onReveal,
        onSpeak: widget.onSpeak ?? () {},
      );
    }
    final content = widget.content;
    if (content is OfficialTemplateContent) {
      return OfficialTemplateWebViewBody(
        content: content,
        isRevealed: widget.isRevealed,
        onReveal: widget.onReveal,
      );
    }
    if (content is StandardCourseCardContent) {
      final interaction = content.interaction;
      if (interaction != null &&
          interaction is! AnkiCard &&
          interaction is! AnkiHtmlCard) {
        return _structured(interaction);
      }
      return FlutterCourseCardBody(
        content: content,
        isRevealed: widget.isRevealed,
        onReveal: widget.onReveal,
        onSpeak: widget.onSpeak ?? () {},
      );
    }
    return const SizedBox.shrink();
  }

  Widget _structured(Interaction interaction) {
    final renderer = lookupRenderer(_renderers, interaction);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: renderer.build(interaction, _state, (correct, {userAnswerText, reviewQuality}) {
              setState(() {
                _state = InteractionState(
                  submitted: true,
                  correct: correct,
                  userAnswerText: userAnswerText,
                );
              });
              _scheduleAck();
              widget.onObjectiveResult?.call(correct);
            }),
          ),
        ),
        if (_state.submitted && widget.onObjectiveResult == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LessonCheckButton(
              label: AppStrings.lessonContinueUpper,
              enabled: true,
              onPressed: widget.onReveal,
            ),
          ),
      ],
    );
  }
}
