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
import 'package:turna/views/theme.dart';

/// Bottom sheet that launches the personalized companion flow
/// (Phase 2.2 of floofy-hugging-hopper).
///
/// Two CTAs target the two halves of the learner's remediation signal:
/// recent mistakes (last 20) or aggregated weak words (same window).
/// Both call [SrsTutorProvider.tutorPlan] with the current AI engine config
/// and on success push the resulting lesson into [NewLessonRoute].
class TutorLaunchSheet extends StatefulWidget {
  const TutorLaunchSheet({super.key});

  @override
  State<TutorLaunchSheet> createState() => _TutorLaunchSheetState();
}

class _TutorLaunchSheetState extends State<TutorLaunchSheet> {
  SrsTutorFocus _focus = SrsTutorFocus.mistakes;
  SrsTutorProvider? _providerRef;

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
    final language = context.read<LanguageProvider>().selectedLanguage.name;
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
    if (lessonId == null)
      return; // error / cancel path is rendered by the body.
    router.pop(); // close the sheet
    router.push(NewLessonRoute(lessonId: lessonId));
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
              AppStrings.tutorLaunchSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _focusChooser(context),
            const SizedBox(height: 16),
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

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded,
            color: TurnaTheme.peacockTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.tutorLaunchTitle,
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
    final tiles = <(SrsTutorFocus, String, IconData)>[
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
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tiles)
          ChoiceChip(
            label: Text(t.$2),
            avatar: Icon(t.$3, size: 18),
            selected: _focus == t.$1,
            onSelected: (_) => setState(() => _focus = t.$1),
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
            return _hint(context, AppStrings.tutorLaunchIdleHint);
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
              color: TurnaTheme.peacockTeal,
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
