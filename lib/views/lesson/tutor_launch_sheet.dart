// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/srs_tutor_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// Bottom sheet that launches the personalized companion flow
/// (Phase 2.2 of floofy-hugging-hopper).
///
/// Two CTAs target the two halves of the learner's remediation signal:
/// recent mistakes (last 20) or aggregated weak words (same window).
/// Both call [SrsTutorProvider.tutorPlan] with the current AI engine config
/// and on success push the resulting lesson into [NewLessonRoute].
///
/// [focus] decides who owns the choice:
///   * `null` — no upstream entry has picked a half yet（学习诊断的单个 CTA）,
///     面板自己渲染 mistakes / weakWords 两个侧重选项；
///   * 非空 — 上游（AI Hub 的两张卡、功能手册页的两张卡）已经选好了，
///     面板不再重复问一遍，只确认并执行。
///
/// 计划 2026-10-20：此前无论从哪进都固定 mistakes + 再渲染一次侧重选择，
/// 造成「大选项点进去又出现同样两个小选项」的重复，且按弱词入口实际开的是错题。
class TutorLaunchSheet extends StatefulWidget {
  const TutorLaunchSheet({super.key, this.focus});

  /// Pre-selected focus. `null` renders the in-sheet chooser.
  final SrsTutorFocus? focus;

  @override
  State<TutorLaunchSheet> createState() => _TutorLaunchSheetState();
}

class _TutorLaunchSheetState extends State<TutorLaunchSheet> {
  late SrsTutorFocus _focus;
  SrsTutorProvider? _providerRef;

  @override
  void initState() {
    super.initState();
    _focus = widget.focus ?? SrsTutorFocus.mistakes;
  }

  @override
  void dispose() {
    // If the user dismisses mid-flight, abort the in-flight call. Captured
    // at initState so dispose() doesn't deref a possibly-stale context.
    _providerRef?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final config = context.read<AiEngineConfigHolder>().config;
    final provider = context.read<SrsTutorProvider>();
    _providerRef = provider;
    final language = context.read<LanguageProvider>().displayName;
    final focus = _focus;
    final router = context.router;

    final lessonId = await provider.tutorPlan(
      config: config,
      language: language,
      focus: focus,
      sectionName: focus == SrsTutorFocus.mistakes
          ? AppStrings.tutorLaunchByMistakesTitle
          : AppStrings.tutorLaunchByWeakWordsTitle,
    );

    if (!mounted) return;
    if (lessonId == null) {
      return; // error / cancel path is rendered by the body.
    }
    router.pop(); // close the sheet
    unawaited(router.push(NewLessonRoute(lessonId: lessonId)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: 6),
            Text(
              _subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (widget.focus == null) ...[
              _focusChooser(context),
              const SizedBox(height: 16),
            ],
            _primaryButton(context),
            const SizedBox(height: 12),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: _status(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 面板标题：上游已选定时用该侧的专属标题，否则用通用「AI 伴学」。
  String get _title => switch (widget.focus) {
        SrsTutorFocus.mistakes => AppStrings.aiHubStartTutorMistakes,
        SrsTutorFocus.weakWords => AppStrings.aiHubStartTutorWeak,
        null => AppStrings.tutorLaunchTitle,
      };

  String get _subtitle => switch (widget.focus) {
        SrsTutorFocus.mistakes => AppStrings.tutorLaunchMistakesSubtitle,
        SrsTutorFocus.weakWords => AppStrings.tutorLaunchWeakSubtitle,
        null => AppStrings.tutorLaunchSubtitle,
      };

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded,
            color: TurnaTheme.brandTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.commonClose,
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => context.router.maybePop(),
        ),
      ],
    );
  }

  Widget _focusChooser(BuildContext context) {
    return TurnaChoiceGrid<SrsTutorFocus>(
      selected: _focus,
      onSelected: (v) => setState(() => _focus = v),
      items: [
        (
          SrsTutorFocus.mistakes,
          AppStrings.tutorLaunchByMistakesCta,
          Icons.history_toggle_off_rounded
        ),
        (
          SrsTutorFocus.weakWords,
          AppStrings.tutorLaunchByWeakWordsCta,
          Icons.quiz_rounded
        ),
      ],
    );
  }

  Widget _primaryButton(BuildContext context) {
    return Selector<SrsTutorProvider, SrsTutorState>(
      selector: (_, w) => w.state,
      builder: (context, state, _) {
        final busy = state == SrsTutorState.gathering ||
            state == SrsTutorState.planning ||
            state == SrsTutorState.saving;
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _run,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.bolt_rounded),
                label: Text(AppStrings.tutorLaunchRun),
              ),
            ),
            if (busy) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: AppStrings.commonCancel,
                onPressed: () => context.read<SrsTutorProvider>().cancel(),
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _status(BuildContext context) {
    return Selector<SrsTutorProvider, _TutorStatus>(
      selector: (_, w) =>
          _TutorStatus(w.state, w.errorMessage, w.generatedSectionName),
      builder: (context, snap, _) {
        switch (snap.state) {
          case SrsTutorState.idle:
            return _hint(
              context,
              widget.focus == null
                  ? AppStrings.tutorLaunchIdleHint
                  : AppStrings.tutorLaunchIdleHintPreselected,
            );
          case SrsTutorState.gathering:
            return _progress(context, AppStrings.tutorLaunchGathering);
          case SrsTutorState.planning:
            return _progress(context, AppStrings.tutorLaunchPlanning);
          case SrsTutorState.ready:
          case SrsTutorState.saving:
            return _progress(context, AppStrings.tutorLaunchSaving);
          case SrsTutorState.saved:
            return _hint(context,
                AppStrings.tutorLaunchSaved(snap.sectionName ?? 'lesson'));
          case SrsTutorState.error:
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TurnaTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              ),
              child: Text(
                snap.errorMessage ?? AppStrings.tutorLaunchErrorUnknown,
                style: const TextStyle(color: TurnaTheme.error),
              ),
            );
        }
      },
    );
  }

  Widget _progress(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: TurnaTheme.brandTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// Lightweight tuple for Selector equality; tuples avoid spurious rebuilds
/// when only [SrsTutorProvider.errorMessage] changes while the state stays
/// the same.
class _TutorStatus {
  const _TutorStatus(this.state, this.errorMessage, this.sectionName);
  final SrsTutorState state;
  final String? errorMessage;
  final String? sectionName;

  @override
  bool operator ==(Object other) =>
      other is _TutorStatus &&
      other.state == state &&
      other.errorMessage == errorMessage &&
      other.sectionName == sectionName;

  @override
  int get hashCode => Object.hash(state, errorMessage, sectionName);
}
