// Flutter imports:
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/read_aloud_gate.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/read_aloud_scoring.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/read_aloud_backend.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

/// 跟读 (read-aloud) card, ADR 0061: show the sentence, speak it as the
/// model, then recognize the learner's utterance and submit a binary verdict
/// derived from word-level matching (`core/read_aloud_scoring.dart`).
///
/// Degradation is structural, not exceptional: when the build has no
/// recognizer (`ReadAloudBackend.isSupported`), the master switch is off, or
/// the mic permission/service failed, the card becomes a listen-only card
/// (the [ListenOnlyRenderer] always-correct pattern) so the lesson never
/// stalls on a capability gap.
@injectable
class ReadAloudRenderer extends InteractionRenderer {
  final ReadAloudBackend _backend;

  ReadAloudRenderer(this._backend);

  @override
  Type get handlesType => ReadAloud;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as ReadAloud;
    return _ReadAloudBody(
      targetText: i.targetText,
      prompt: i.prompt,
      backend: _backend,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _ReadAloudBody extends StatefulWidget {
  final String targetText;
  final String prompt;
  final ReadAloudBackend backend;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _ReadAloudBody({
    required this.targetText,
    required this.prompt,
    required this.backend,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_ReadAloudBody> createState() => _ReadAloudBodyState();
}

class _ReadAloudBodyState extends State<_ReadAloudBody> {
  bool _listening = false;
  String? _partial;
  String? _trouble;
  bool _gaveUpMic = false;
  ReadAloudScore? _score;

  /// Sentinel userAnswerText recorded when the card degraded — distinguishes
  /// "answered via mic" from "listened through" in restored state.
  static const String _degradedAnswer = 'read-aloud-degraded';

  @override
  void initState() {
    super.initState();
    maybeAutoSpeak(_speak);
  }

  @override
  void dispose() {
    // Ending the session here is best-effort cleanup; the backend delivers a
    // final result nobody listens to anymore.
    if (_listening) unawaited(widget.backend.stop());
    super.dispose();
  }

  Future<void> _speak() async {
    if (_listening) {
      unawaited(widget.backend.stop());
      setState(() => _listening = false);
    }
    try {
      if (getIt.isRegistered<AudioController>()) {
        await getIt<AudioController>().speak(
          widget.targetText,
          languageCode: currentSpeechLanguages().target,
        );
      }
    } catch (_) {
      // GetIt optional dependency guard for unit tests without audio graph
    }
  }

  Future<void> _onMicTap() async {
    if (widget.state.submitted) return;
    if (_listening) {
      // Tap-to-stop: the backend delivers the final transcript through the
      // same onResult channel, so scoring happens in one place.
      unawaited(widget.backend.stop());
      return;
    }
    // Stop any in-flight model TTS so mic does not pick up phone speaker audio
    try {
      if (getIt.isRegistered<AudioController>()) {
        unawaited(getIt<AudioController>().stopSystemTts());
      }
    } catch (_) {
      // Best-effort cleanup when AudioController is not registered in test harness
    }

    final ready = await widget.backend.ensureReady();
    if (!mounted || widget.state.submitted) return;
    if (!ready) {
      setState(() {
        _gaveUpMic = true;
        _trouble = AppStrings.readAloudPermissionDenied;
      });
      return;
    }
    setState(() {
      _listening = true;
      _partial = null;
      _trouble = null;
    });
    await widget.backend.start(
      // The course's target language: the recognizer needs the right locale
      // or it transcribes Turkish as if it were the device language.
      locale: currentSpeechLanguages().target,
      onResult: _onResult,
      onError: _onError,
    );
  }

  void _onResult(String text, bool isFinal) {
    if (!mounted || widget.state.submitted) return;
    if (!isFinal) {
      setState(() => _partial = text);
      return;
    }
    setState(() => _listening = false);
    if (text.trim().isEmpty) {
      // Recognition ended with nothing usable — not an answer, so no
      // submission: the learner can tap the mic again.
      setState(() => _trouble = AppStrings.readAloudNoMatch);
      return;
    }
    final score = scoreReadAloud(widget.targetText, text);
    setState(() => _score = score);
    widget.onSubmit(score.passed, userAnswerText: text);
  }

  void _onError(ReadAloudFailure reason) {
    if (!mounted || widget.state.submitted) return;
    setState(() {
      _listening = false;
      _trouble = switch (reason) {
        ReadAloudFailure.permissionDenied =>
          AppStrings.readAloudPermissionDenied,
        ReadAloudFailure.serviceUnavailable ||
        ReadAloudFailure.recognitionFailed =>
          AppStrings.readAloudNoMatch,
      };
    });
  }

  Future<void> _enableAndStay() async {
    // In-card one-tap enable (the approved default-off posture): flip the
    // master switch without leaving the lesson; the rebuild shows the mic.
    final settings = getIt<SettingsProvider>();
    await settings.setReadAloudExercisesEnabled(true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.state.submitted;
    final micAvailable = widget.backend.isSupported && !_gaveUpMic;
    final gateOn = readAloudExercisesEnabled();
    // Restored after re-entry: the score is a pure function of the target and
    // the recorded transcript, so it is recomputed rather than persisted.
    final score = _score ??
        (submitted &&
                widget.state.userAnswerText != null &&
                widget.state.userAnswerText != _degradedAnswer
            ? scoreReadAloud(widget.targetText, widget.state.userAnswerText!)
            : null);

    if (!micAvailable || !gateOn) {
      return _DegradedBody(
        targetText: widget.targetText,
        prompt: widget.prompt,
        // When the mic path was tried and refused (permission / no service),
        // the refusal itself is the most useful note; the generic hints are
        // for cards that degraded before any attempt.
        note: _gaveUpMic && _trouble != null
            ? _trouble!
            : !micAvailable
                ? AppStrings.readAloudDegradedHint
                : AppStrings.readAloudEnableHint,
        enableOffered: !gateOn && micAvailable,
        submitted: submitted,
        onEnable: _enableAndStay,
        onSpeak: _speak,
        onSubmit: () => widget.onSubmit(true, userAnswerText: _degradedAnswer),
      );
    }

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.readAloudCaption),
          const SizedBox(height: 8),
          Text(
            widget.prompt,
            textAlign: TextAlign.center,
            style: AppTextStyles.promptMd(context),
          ),
          const SizedBox(height: 24),
          _TargetWords(score: score, targetText: widget.targetText),
          const SizedBox(height: 16),
          Center(
            child: SpeakerButton(
              onPressed: _speak,
            ),
          ),
          const SizedBox(height: 20),
          Center(child: _MicButton(listening: _listening, onTap: _onMicTap)),
          const SizedBox(height: 12),
          Text(
            _listening
                ? AppStrings.readAloudListening
                : AppStrings.readAloudMicHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
            textAlign: TextAlign.center,
          ),
          if (_partial != null && _listening) ...[
            const SizedBox(height: 12),
            Text(
              _partial!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                    fontStyle: FontStyle.italic,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (_trouble != null) ...[
            const SizedBox(height: 12),
            Text(
              _trouble!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (submitted && score != null) ...[
            const SizedBox(height: 16),
            Text(
              '${AppStrings.readAloudHeardPrefix}${widget.state.userAnswerText ?? ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
          if (submitted && widget.state.correct == false) ...[
            const SizedBox(height: 16),
            LessonCorrectAnswerBanner(
              label: AppStrings.lessonCorrectAnswer,
              answer: widget.targetText,
            ),
          ],
        ],
      ),
    );
  }
}

/// The sentence to read: plain before any attempt, word-by-word colored
/// feedback afterwards (matched / not heard — intelligibility wording, never
/// "wrong pronunciation", per ADR 0061).
class _TargetWords extends StatelessWidget {
  const _TargetWords({required this.score, required this.targetText});

  final ReadAloudScore? score;
  final String targetText;

  @override
  Widget build(BuildContext context) {
    final outcome = score;
    if (outcome == null) {
      return Text(
        targetText,
        key: const ValueKey('read-aloud-target'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: TurnaTheme.textPrimaryColor(context),
        ),
      );
    }
    return Wrap(
      key: const ValueKey('read-aloud-words'),
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final word in outcome.words)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (word.matched ? TurnaTheme.success : TurnaTheme.error)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
              border: Border.all(
                color: (word.matched ? TurnaTheme.success : TurnaTheme.error)
                    .withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              word.word,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: word.matched ? TurnaTheme.successDark : TurnaTheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// Circular mic button; doubles as stop while listening.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onTap});

  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = listening ? TurnaTheme.error : TurnaTheme.brandTeal;
    return Semantics(
      button: true,
      label: listening ? AppStrings.readAloudStop : AppStrings.readAloudMicHint,
      child: Tooltip(
        message:
            listening ? AppStrings.readAloudStop : AppStrings.readAloudMicHint,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: listening ? 0.5 : 0.25),
                blurRadius: listening ? 16 : 8,
                spreadRadius: listening ? 4 : 0,
              ),
            ],
          ),
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: TurnaTheme.textOnPrimary,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Listen-only fallback card (the [ListenOnlyRenderer] shape): model audio +
/// continue, always-correct submission. Offers the in-card enable toggle when
/// the only obstacle is the master switch.
class _DegradedBody extends StatelessWidget {
  const _DegradedBody({
    required this.targetText,
    required this.prompt,
    required this.note,
    required this.enableOffered,
    required this.submitted,
    required this.onEnable,
    required this.onSpeak,
    required this.onSubmit,
  });

  final String targetText;
  final String prompt;
  final String note;
  final bool enableOffered;
  final bool submitted;
  final VoidCallback onEnable;
  final VoidCallback onSpeak;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.readAloudCaption),
          const SizedBox(height: 8),
          Text(
            prompt,
            textAlign: TextAlign.center,
            style: AppTextStyles.promptMd(context),
          ),
          const SizedBox(height: 20),
          Text(
            targetText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: TurnaTheme.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: SpeakerButton(onPressed: onSpeak)),
          const SizedBox(height: 12),
          Text(
            note,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
            textAlign: TextAlign.center,
          ),
          if (enableOffered) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onEnable,
              icon: const Icon(Icons.mic_rounded),
              label: Text(AppStrings.readAloudEnableAction),
            ),
          ],
          const SizedBox(height: 28),
          LessonCheckButton(
            label: submitted
                ? AppStrings.commonDone
                : AppStrings.lessonContinueUpper,
            enabled: !submitted,
            onPressed: submitted ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}
