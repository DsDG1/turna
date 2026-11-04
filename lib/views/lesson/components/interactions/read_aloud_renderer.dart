// Flutter imports:
import 'dart:async' show Timer, unawaited;

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
import 'package:turna/views/lesson/components/interactions/interaction_fields.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

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
  bool _starting = false;
  String? _partial;
  String? _trouble;
  bool _gaveUpMic = false;
  ReadAloudScore? _score;

  /// How long a session may stay silent before the status hint is replaced
  /// and a skip button appears — the last-resort net under the backend's
  /// watchdogs, so the card can never sit in "listening" forever.
  static const Duration _stallAfter = Duration(seconds: 10);
  Timer? _stallTimer;
  bool _stalled = false;

  /// Set by [_onSkip]: `state.submitted` may not flip synchronously, so a
  /// late final transcript needs a local guard too.
  bool _skipped = false;

  /// Sentinel userAnswerText recorded when the card degraded — distinguishes
  /// "answered via mic" from "listened through" in restored state.
  static const String _degradedAnswer = 'read-aloud-degraded';

  /// Sentinel for the stall escape hatch: a technical stall is not an
  /// answer, so it neither scores nor lands in the wrong book.
  static const String _skippedAnswer = 'read-aloud-skipped';

  @override
  void initState() {
    super.initState();
    maybeAutoSpeak(_speak);
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    // Ending the session here is best-effort cleanup; the backend delivers a
    // final result nobody listens to anymore.
    if (_listening) unawaited(widget.backend.stop());
    super.dispose();
  }

  Future<void> _speak() async {
    if (_starting) return;
    if (_listening) {
      await widget.backend.stop();
      if (!mounted) return;
      setState(() => _listening = false);
    }
    try {
      if (getIt.isRegistered<AudioController>()) {
        final result = await getIt<AudioController>().speakWithResult(
          widget.targetText,
          languageCode: currentSpeechLanguages().target,
        );
        if (mounted) showTtsFailureFeedback(context, result);
      }
    } catch (_) {
      // GetIt optional dependency guard for unit tests without audio graph
    }
  }

  Future<void> _onMicTap() async {
    if (widget.state.submitted || _starting) return;
    if (_listening) {
      // Tap-to-stop: the backend delivers the final transcript through the
      // same onResult channel, so scoring happens in one place.
      unawaited(widget.backend.stop());
      return;
    }
    _starting = true;
    try {
      // The native stop must finish before recognition opens the microphone.
      try {
        if (getIt.isRegistered<AudioController>()) {
          await getIt<AudioController>().stopSystemTts();
        }
      } catch (_) {
        // GetIt optional dependency guard for unit tests without audio graph
      }

      final ready = await widget.backend.ensureReady();
      if (!mounted || widget.state.submitted) return;
      if (!ready) {
        final failure =
            widget.backend.lastFailure ?? ReadAloudFailure.permissionDenied;
        setState(() {
          _gaveUpMic = true;
          _trouble = _failureText(failure);
        });
        return;
      }
      setState(() {
        _listening = true;
        _partial = null;
        _trouble = null;
        _stalled = false;
      });
      _armStallWatch();
      await widget.backend.start(
        // The course's target language: the recognizer needs the right locale
        // or it transcribes Turkish as if it were the device language.
        locale: currentSpeechLanguages().target,
        onResult: _onResult,
        onError: _onError,
      );
    } finally {
      _starting = false;
    }
  }

  void _onResult(String text, bool isFinal) {
    if (!mounted || _skipped || widget.state.submitted) return;
    if (!isFinal) {
      // Ongoing speech keeps pushing the stall hint back.
      _armStallWatch();
      setState(() => _partial = text);
      return;
    }
    _stallTimer?.cancel();
    setState(() {
      _listening = false;
      _stalled = false;
    });
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

  void _armStallWatch() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallAfter, () {
      _stallTimer = null;
      if (!mounted || _skipped || widget.state.submitted) return;
      setState(() => _stalled = true);
    });
  }

  void _onSkip() {
    if (widget.state.submitted || _skipped) return;
    _stallTimer?.cancel();
    // Best-effort teardown; a late final transcript is dropped by the
    // `_skipped` guard rather than scored.
    unawaited(widget.backend.stop());
    setState(() {
      _listening = false;
      _stalled = false;
      _skipped = true;
    });
    // Same posture as the degraded card: progress never blocks on a
    // technical stall, and nothing lands in the wrong book.
    widget.onSubmit(true, userAnswerText: _skippedAnswer);
  }

  String _failureText(ReadAloudFailure reason) => switch (reason) {
        ReadAloudFailure.permissionDenied =>
          AppStrings.readAloudPermissionDenied,
        ReadAloudFailure.serviceUnavailable =>
          AppStrings.readAloudServiceUnavailable,
        ReadAloudFailure.networkUnavailable =>
          AppStrings.readAloudNetworkUnavailable,
        ReadAloudFailure.recognitionFailed => AppStrings.readAloudNoMatch,
      };

  void _onError(ReadAloudFailure reason) {
    if (!mounted || widget.state.submitted || _skipped) return;
    _stallTimer?.cancel();
    setState(() {
      _listening = false;
      _trouble = _failureText(reason);
      _stalled = false;
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
    // Sentinel answers carry no transcript to score.
    final score = _score ??
        (submitted &&
                widget.state.userAnswerText != null &&
                widget.state.userAnswerText != _degradedAnswer &&
                widget.state.userAnswerText != _skippedAnswer
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
          // 阶段 1（§7.1 跟读）: 示例句在纸面画布上, 提交后原地变词面结果。
          SessionRecallCanvas(
            minHeight: 200,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.prompt,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.promptMd(context),
                ),
                const SizedBox(height: 16),
                _TargetWords(score: score, targetText: widget.targetText),
              ],
            ),
          ),
          // 阶段 2: 示范播放（行内描边档）; 阶段 3: 录音主控。
          const SizedBox(height: 20),
          Center(child: SpeakerButton(onPressed: _speak)),
          const SizedBox(height: 20),
          Center(child: _MicButton(listening: _listening, onTap: _onMicTap)),
          const SizedBox(height: 12),
          Text(
            _stalled
                ? AppStrings.readAloudStalledHint
                : _listening
                    ? AppStrings.readAloudListening
                    : AppStrings.readAloudMicHint,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
            textAlign: TextAlign.center,
          ),
          if (_stalled && !submitted) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(
                onPressed: _onSkip,
                child: Text(AppStrings.readAloudSkipAction),
              ),
            ),
          ],
          if (_partial != null && _listening) ...[
            const SizedBox(height: 12),
            Text(
              _partial!,
              style: AppTextStyles.captionSm(context).copyWith(
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
              style: AppTextStyles.captionSm(context).copyWith(
                color: TurnaTheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (submitted && score != null) ...[
            const SizedBox(height: 16),
            Text(
              '${AppStrings.readAloudHeardPrefix}${widget.state.userAnswerText ?? ''}',
              style: AppTextStyles.captionSm(context).copyWith(
                color: TurnaTheme.textHintColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          // 跟读的词面结果本身就是结果层, 答对不再叠一行轻结果; 只有
          // 未通过时给「听到 → 目标句」对照（§7.2 第 4 段）。
          if (submitted && widget.state.correct == false) ...[
            const SizedBox(height: 16),
            InteractionFeedbackPanel(
              correct: false,
              userAnswer: widget.state.userAnswerText,
              correctAnswer: widget.targetText,
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
        style: AppTextStyles.termHero(context)
            .copyWith(fontSize: 24, height: 1.4),
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
///
/// 光晕走主题的同色相投影 token（与 SpeakerHero 同一材质语言）; 录音中
/// 用一圈语义色描边环表达"正在收音", 不再手写 blur/alpha 字面量。
class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onTap});

  final bool listening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = listening ? TurnaTheme.error : TurnaTheme.brandTeal;
    Widget core = Material(
      color: color,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
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
    );
    if (listening) {
      core = Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
        ),
        child: core,
      );
    }
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
            boxShadow: TurnaTheme.glassShadow(
              context,
              color,
              level: GlassLevel.l2,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: core,
          ),
        ),
      ),
    );
  }
}

/// Listen-only fallback card (the [ListenOnlyRenderer] shape): model audio +
/// band CTA, always-correct submission. Offers the in-card enable toggle when
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
    // 「继续」CTA 交给页面底栏（P1：主操作跨题型位置稳定），提交语义不变。
    LessonActionScope.maybeOf(context)?.report(
      canSubmit: !submitted,
      submit: onSubmit,
      label: AppStrings.lessonContinueUpper,
    );

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppStrings.readAloudCaption),
          // 降级体 = 听示范卡（ADR 0061）: 与 ListenOnly 同构图, 播放主控
          // 是视觉中心, 权限/不可用提示原位呈现（§7.1 跟读）。
          SessionRecallCanvas(
            minHeight: 240,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  prompt,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.promptMd(context),
                ),
                const SizedBox(height: 16),
                Text(
                  targetText,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.termHero(context).copyWith(fontSize: 24),
                ),
                const SizedBox(height: 24),
                SpeakerHero(onPressed: onSpeak),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            note,
            style: AppTextStyles.captionSm(context).copyWith(
              color: TurnaTheme.textHintColor(context),
            ),
            textAlign: TextAlign.center,
          ),
          if (enableOffered) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: onEnable,
                icon: const Icon(Icons.mic_rounded),
                label: Text(AppStrings.readAloudEnableAction),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
