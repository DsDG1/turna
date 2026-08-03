// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki/anki_canonical_card_loader.dart';
import 'package:turna/application/anki/anki_type_answer.dart';
import 'package:turna/application/anki/anki_template_renderer.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/html_stripper.dart';
import 'package:turna/core/language_detector.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_html_card_view.dart';
import 'package:turna/views/lesson/components/anki_media_strip.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/theme.dart';

/// Fidelity-track renderer for [AnkiHtmlCard] (deep-adaptation plan §5).
///
/// Shows the rendered front HTML; the user taps "Show Answer" to swap to the
/// back HTML, then grades with Anki's four official answer buttons. The HTML
/// faces are rendered by
/// `AnkiCardHtmlRenderer` from the NoteStore and displayed by
/// [AnkiHtmlCardView] (WebView on Android/iOS, text fallback elsewhere).
@injectable
class AnkiHtmlCardRenderer extends InteractionRenderer {
  @override
  Type get handlesType => AnkiHtmlCard;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as AnkiHtmlCard;
    return _AnkiHtmlCardBody(
      interaction: i,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _AnkiHtmlCardBody extends StatefulWidget {
  final AnkiHtmlCard interaction;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _AnkiHtmlCardBody({
    required this.interaction,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_AnkiHtmlCardBody> createState() => _AnkiHtmlCardBodyState();
}

class _AnkiHtmlCardBodyState extends State<_AnkiHtmlCardBody> {
  bool _revealed = false;
  String _typedAnswer = '';
  AnkiHtmlCard? _resolvedInteraction;
  Object? _loadError;

  /// Stripped speakable text + resolved TTS languages for the current card.
  /// Recomputed (lazily) whenever the underlying card changes (lazy reference
  /// resolution, didUpdateWidget word-id change).
  String _frontText = '';
  String _backText = '';
  ({String front, String back})? _pair;

  bool get _isLazyReference =>
      widget.interaction.frontHtml.isEmpty &&
      widget.interaction.backHtml.isEmpty &&
      widget.interaction.wordId != null;

  @override
  void initState() {
    super.initState();
    _resolveLazyReference();
    _maybeAutoSpeakFront();
  }

  @override
  void didUpdateWidget(covariant _AnkiHtmlCardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interaction.wordId != widget.interaction.wordId) {
      _revealed = false;
      _typedAnswer = '';
      _resolvedInteraction = null;
      _loadError = null;
      _pair = null;
      _frontText = '';
      _backText = '';
      _resolveLazyReference();
      _maybeAutoSpeakFront();
    }
  }

  Future<void> _resolveLazyReference() async {
    if (!_isLazyReference) return;
    try {
      final resolved = await AnkiCanonicalCardLoader(getIt<AnkiNoteDao>())
          .load(widget.interaction.wordId!);
      if (!mounted) return;
      setState(() {
        _resolvedInteraction = resolved;
        if (resolved == null) {
          _loadError = StateError('Anki card source is missing');
        }
      });
      if (resolved != null) {
        // Card text is now available -> (re)evaluate auto-speak front.
        _pair = null;
        _maybeAutoSpeakFront();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  /// Compute [_frontText]/[_backText]/[_pair] from the effective card. Cheap
  /// (cached); invalidated when the underlying card changes.
  void _ensurePair() {
    if (_pair != null) return;
    final i = _resolvedInteraction ?? widget.interaction;
    _frontText = stripHtml(i.frontHtml);
    _backText = stripHtml(i.backHtml);
    final langs = currentSpeechLanguages();
    _pair = const LanguageDetector().detectCardPair(
      _frontText,
      _backText,
      targetLanguage: langs.target,
      nativeLanguage: langs.native,
    );
  }

  void _speakFace(String text, String? lang) {
    if (text.trim().isEmpty) return;
    getIt<AudioController>().speak(text, languageCode: lang);
  }

  void _speakFront() {
    _ensurePair();
    _speakFace(_frontText, _pair?.front);
  }

  void _speakBack() {
    _ensurePair();
    _speakFace(_backText, _pair?.back);
  }

  /// Auto-read the front face when the card first appears (or finishes lazy
  /// loading), if the course's auto-read toggle is on.
  void _maybeAutoSpeakFront() {
    if (!autoReadOnTapForActiveCourse()) return;
    _ensurePair();
    final text = _frontText;
    if (text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _speakFace(text, _pair?.front);
    });
  }

  /// Auto-read the back face on reveal when the course toggle is on.
  void _onRevealBack() {
    if (!autoReadOnTapForActiveCourse()) return;
    _ensurePair();
    _speakFace(_backText, _pair?.back);
  }

  void _grade({
    required bool correct,
    required String label,
    required AnkiReviewRating rating,
  }) {
    widget.onSubmit(
      correct,
      userAnswerText: label,
      reviewQuality: rating.quality,
    );
  }

  void _toggleFace() {
    setState(() => _revealed = !_revealed);
    if (_revealed) _onRevealBack();
  }

  void _showBack() {
    if (!_revealed) {
      setState(() => _revealed = true);
      _onRevealBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLazyReference && _resolvedInteraction == null) {
      return InteractionBody(
        child: Center(
          child: _loadError == null
              ? const CircularProgressIndicator()
              : Text(
                  'Anki card could not be loaded: $_loadError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TurnaTheme.error),
                ),
        ),
      );
    }
    final i = _resolvedInteraction ?? widget.interaction;
    final typeAnswer = AnkiTemplateRenderer.extractTypeAnswer(i.backHtml);
    // Advanced settings (deep-adaptation plan): force-disable JS overrides
    // allowJs; pre-render gates the capture; captureDelay tunes the wait.
    final forceDisableJs =
        context.select<SettingsProvider, bool>((p) => p.ankiForceDisableJs);
    final preRender =
        context.select<SettingsProvider, bool>((p) => p.ankiPreRenderEnabled);
    final captureDelaySec =
        context.select<SettingsProvider, int>((p) => p.ankiCaptureDelaySec);
    final effectiveAllowJs = i.allowJs && !forceDisableJs;
    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.lessonFlipCardCaption),
          Semantics(
            button: true,
            label: _revealed
                ? AppStrings.lessonTapToReturnFront
                : AppStrings.lessonTapToReveal,
            child: GestureDetector(
              key: const ValueKey('anki-html-flip-card-surface'),
              behavior: HitTestBehavior.translucent,
              onTap: _toggleFace,
              child: SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: TurnaTheme.cardBg(context),
                      border: Border.all(
                        color: TurnaTheme.statCardBorder(context),
                      ),
                    ),
                    child: AnkiHtmlCardView(
                      html: _revealed ? i.backHtml : i.frontHtml,
                      allowJs: effectiveAllowJs,
                      dark: Theme.of(context).brightness == Brightness.dark,
                      allowedMediaBasePath: i.mediaBasePath,
                      hideEmbeddedAudioControls: i.audioAssets.isNotEmpty,
                      isBack: _revealed,
                      typeAnswerEnabled: !_revealed &&
                          typeAnswer != null &&
                          typeAnswer.isNotEmpty,
                      onTypeAnswerChanged: (value) =>
                          setState(() => _typedAnswer = value),
                      captureDelay: Duration(seconds: captureDelaySec),
                      // "智能去解密": capture the decrypted DOM after the JS runs and
                      // cache it, so later reviews of this card skip the JS. Only
                      // when JS is effective + pre-render enabled + has a wordId.
                      onCaptured:
                          effectiveAllowJs && preRender && i.wordId != null
                              ? (html, isBack) async {
                                  // Best-effort "智能去解密" cache write: must
                                  // not throw into the review flow, so DB
                                  // errors are logged instead of surfacing.
                                  try {
                                    await getIt<AnkiNoteDao>()
                                        .upsertPrerenderedFace(
                                      i.wordId!,
                                      front: isBack ? null : html,
                                      back: isBack ? html : null,
                                    );
                                  } catch (e, st) {
                                    debugPrint(
                                      'anki: prerendered-face cache write '
                                      'failed: $e\n$st',
                                    );
                                  }
                                }
                              : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (i.audioAssets.isNotEmpty) ...[
            const SizedBox(height: 8),
            AnkiMediaStrip(audioAssets: i.audioAssets),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.record_voice_over_rounded),
                color: TurnaTheme.peacockTeal,
                tooltip: AppStrings.lessonSpeakLabel,
                onPressed: _revealed ? _speakBack : _speakFront,
              ),
              TextButton.icon(
                key: const ValueKey('anki-html-flip-button'),
                onPressed: _toggleFace,
                icon: const Icon(Icons.flip_rounded, size: 18),
                label: Text(
                  _revealed
                      ? AppStrings.lessonTapToReturnFront
                      : AppStrings.lessonTapToReveal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_revealed && typeAnswer != null && typeAnswer.isNotEmpty)
            _buildTypeFeedback(context, typeAnswer),
          if (_revealed) const SizedBox(height: 12),
          if (!widget.state.submitted) ...[
            if (!_revealed)
              LessonCheckButton(
                label: AppStrings.lessonShowAnswer,
                enabled: true,
                onPressed: _showBack,
              )
            else
              _buildGradeButtons(context),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeFeedback(BuildContext context, String expected) {
    final result = AnkiTypeAnswerMatcher.compare(expected, _typedAnswer);
    final color = result.correct ? TurnaTheme.success : TurnaTheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.correct ? '输入正确' : '输入不匹配',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('你的答案：${_typedAnswer.isEmpty ? '（未输入）' : _typedAnswer}'),
          if (!result.correct) Text('正确答案：$expected'),
        ],
      ),
    );
  }

  Widget _buildGradeButtons(BuildContext context) {
    return Column(
      children: [
        Text(
          AppStrings.lessonHowWellDidYouKnow,
          style: TextStyle(
            fontSize: 14,
            color: TurnaTheme.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewAgain,
                color: TurnaTheme.error,
                onPressed: () => _grade(
                  correct: false,
                  label: AppStrings.reviewAgain,
                  rating: AnkiReviewRating.again,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewHard,
                color: TurnaTheme.warning,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewHard,
                  rating: AnkiReviewRating.hard,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewGood,
                color: TurnaTheme.success,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewGood,
                  rating: AnkiReviewRating.good,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _GradeButton(
                label: AppStrings.reviewEasy,
                color: TurnaTheme.peacockTeal,
                onPressed: () => _grade(
                  correct: true,
                  label: AppStrings.reviewEasy,
                  rating: AnkiReviewRating.easy,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _GradeButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    );
  }
}
