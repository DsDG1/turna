// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_diagnosis_provider.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/lesson/tutor_launch_sheet.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class AiDiagnosisPage extends StatefulWidget {
  const AiDiagnosisPage({super.key});

  @override
  State<AiDiagnosisPage> createState() => _AiDiagnosisPageState();
}

class _AiDiagnosisPageState extends State<AiDiagnosisPage> {
  late final AiDiagnosisProvider _provider;

  @override
  void initState() {
    super.initState();
    AiExplainPrefsStore? prefs;
    try {
      prefs = context.read<AiExplainPrefsStore>();
    } catch (_) {}
    _provider = AiDiagnosisProvider(prefs: prefs);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<LearnerAiContext> _buildContext() async {
    const language = 'Turkish';

    final mistakes = <String>[];
    try {
      final mp = context.read<MistakeProvider>();
      for (final e in mp.entries.take(12)) {
        mistakes.add(LearnerAiContext.summarizeMistake(
          prompt: e.interactionId.isNotEmpty
              ? e.interactionId
              : e.lessonId,
          userAnswer: e.userAnswer,
        ));
      }
    } catch (_) {}

    final weak = <String>[];
    try {
      final stats = context.read<StudyStatsProvider>();
      final words = await stats.getWeakWords(limit: 8);
      for (final w in words) {
        weak.add(w.displayText);
      }
    } catch (_) {}

    return LearnerAiContext.assemble(
      languageName: language,
      recentMistakeSummaries: mistakes,
      weakTerms: weak,
    );
  }

  Future<void> _generate({bool force = false}) async {
    final config = context.read<AiEngineConfigHolder>().config;
    final ctx = await _buildContext();
    if (!mounted) return;
    if (ctx.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppStrings.aiDiagnosisEmpty)),
      );
      return;
    }
    final ok = await _provider.generate(
      config: config,
      learnerContext: ctx,
      force: force,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppStrings.aiDiagnosisRateLimited)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: AppBar(
          title: Text(
            AppStrings.aiDiagnosisTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        body: SafeArea(
          child: Consumer2<AiDiagnosisProvider, AiEngineConfigHolder>(
            builder: (context, p, holder, _) {
              if (!holder.config.isComplete) {
                return const Center(child: AiNotConfiguredPanel());
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    AppStrings.aiDisclaimer,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: p.state == AiDiagnosisState.loading
                        ? null
                        : () => _generate(),
                    icon: p.state == AiDiagnosisState.loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.analytics_outlined),
                    label: Text(AppStrings.aiDiagnosisGenerate),
                    style: FilledButton.styleFrom(
                      backgroundColor: TurnaTheme.brandTeal,
                    ),
                  ),
                  if (p.error != null && p.error != 'rate_limited') ...[
                    const SizedBox(height: 12),
                    Text(p.error!,
                        style: const TextStyle(color: TurnaTheme.error)),
                  ],
                  if (p.report != null) ...[
                    const SizedBox(height: 24),
                    _section(
                      context,
                      AppStrings.aiDiagnosisWeakAreas,
                      [
                        for (final a in p.report!.weakAreas)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('[${a.severity}] ${a.title}'),
                            subtitle: a.evidence.isEmpty
                                ? null
                                : Text(a.evidence.join(' · ')),
                          ),
                      ],
                    ),
                    _section(
                      context,
                      AppStrings.aiDiagnosisTips,
                      [
                        for (final t in p.report!.priorityTips)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.lightbulb_outline),
                            title: Text(t),
                          ),
                      ],
                    ),
                    _section(
                      context,
                      AppStrings.aiDiagnosisDrills,
                      [
                        for (final t in p.report!.exampleDrillIdeas)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.fitness_center),
                            title: Text(t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            final text = p.report!.toPlainText();
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(
                                  content: Text(AppStrings.aiDepthCopied)),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded),
                          label: Text(AppStrings.aiDepthCopy),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final store =
                                context.read<AiSavedExplanationsStore>();
                            await store.save(SavedExplanation(
                              id: AiSavedExplanationsStore.newId(),
                              title: AppStrings.aiDiagnosisTitle,
                              body: p.report!.toPlainText(),
                              source: 'diagnosis',
                              createdAt: DateTime.now(),
                            ));
                            if (context.mounted) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                    content:
                                        Text(AppStrings.aiExplanationSaved)),
                              );
                            }
                          },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(AppStrings.aiSaveExplanation),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: TurnaTheme.cardBg(context),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(TurnaTheme.radiusXLarge),
                            ),
                          ),
                          builder: (_) => const TutorLaunchSheet(),
                        );
                      },
                      icon: const Icon(Icons.school_outlined),
                      label: Text(AppStrings.aiDiagnosisSecondaryCta),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }
}
