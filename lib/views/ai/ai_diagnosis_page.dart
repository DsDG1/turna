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
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/ai/learner_ai_context.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_error_banner.dart';
import 'package:turna/views/ai/components/ai_not_configured_panel.dart';
import 'package:turna/views/ai/components/ai_practice_generate_sheet.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 学习诊断 —— 纵向报告构图（R14）：**结论 → 依据 → 建议 → 行动**。
///
/// * 结论：[ReportMetricHeader]（薄弱点数量开篇）；
/// * 依据：薄弱点行（标题 + 程度短值在右、证据小字在下，发丝线分隔）；
/// * 建议：优先建议与可练想法的编号行；
/// * 行动：目录入口（生成练习 / 收藏 / 复制）。
///
/// 生成 / 停止在底部动作带（位置跨页稳定），流式中断与失败重试保持。
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
    } catch (_) {/* prefs provider optional — fall back to defaults */}
    _provider = AiDiagnosisProvider(prefs: prefs);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  Future<LearnerAiContext> _buildContext() async {
    final language = context.read<LanguageProvider>().displayName;

    final mistakes = <String>[];
    try {
      final mp = context.read<MistakeProvider>();
      for (final e in mp.entries.take(12)) {
        mistakes.add(LearnerAiContext.summarizeMistake(
          prompt: e.interactionId.isNotEmpty ? e.interactionId : e.lessonId,
          userAnswer: e.userAnswer,
        ));
      }
    } catch (_) {
      /* MistakeProvider optional — assemble without mistake summary */
    }

    final weak = <String>[];
    try {
      final stats = context.read<StudyStatsProvider>();
      final words = await stats.getWeakWords(limit: 8);
      for (final w in words) {
        weak.add(w.displayText);
      }
    } catch (_) {/* StudyStatsProvider optional — skip weak-word section */}

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
      TurnaSnackBar.maybeShow(context, AppStrings.aiDiagnosisEmpty);
      return;
    }
    final ok = await _provider.generate(
      config: config,
      learnerContext: ctx,
      force: force,
    );
    if (!ok && mounted) {
      TurnaSnackBar.maybeShow(context, AppStrings.aiDiagnosisRateLimited);
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
              return Column(
                children: [
                  Expanded(
                    child: p.report == null
                        ? _IdleBody(provider: p)
                        : _ReportBody(provider: p),
                  ),
                  // 底部动作带：生成 / 停止位置稳定；失败重试就近。
                  SessionActionBand(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageMargin,
                      AppSpacing.md,
                      AppSpacing.pageMargin,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (p.errorMapping != null) ...[
                          AiErrorBanner(
                            mapping: p.errorMapping!,
                            onRetry: () => _generate(force: true),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        SessionPrimaryAction(
                          label: p.state == AiDiagnosisState.loading
                              ? AppStrings.aiStopGenerating
                              : AppStrings.aiDiagnosisGenerate,
                          onPressed: p.state == AiDiagnosisState.loading
                              ? p.cancel
                              : () => _generate(),
                          trailingIcon: p.state == AiDiagnosisState.loading
                              ? Icons.stop_rounded
                              : Icons.analytics_outlined,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 尚无报告时的等待态：一句结论预告 + 免责声明。
class _IdleBody extends StatelessWidget {
  const _IdleBody({required this.provider});

  final AiDiagnosisProvider provider;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageMargin),
      children: [
        ReportMetricHeader(
          label: AppStrings.aiDiagnosisSectionConclusion,
          value: provider.state == AiDiagnosisState.loading ? '…' : '—',
          unit: AppStrings.aiDiagnosisWeakAreaUnit,
          caption: AppStrings.aiDisclaimer,
        ),
      ],
    );
  }
}

/// 四段式报告正文。
class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.provider});

  final AiDiagnosisProvider provider;

  @override
  Widget build(BuildContext context) {
    final report = provider.report!;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.pageMargin),
      children: [
        // ── 结论 ──
        ReportMetricHeader(
          label: AppStrings.aiDiagnosisSectionConclusion,
          value: '${report.weakAreas.length}',
          unit: AppStrings.aiDiagnosisWeakAreaUnit,
          caption: AppStrings.aiDisclaimer,
        ),
        const SizedBox(height: AppSpacing.xl),

        // ── 依据：薄弱点行（标题 + 程度 + 证据）──
        if (report.weakAreas.isNotEmpty) ...[
          ReportSectionHeading(
              title: AppStrings.aiDiagnosisSectionEvidence),
          ReportDefinitionList(
            rows: [
              for (final a in report.weakAreas)
                ReportDefinitionRow(
                  label: a.title,
                  value: _severityLabel(a.severity),
                  valueColor: _severityColor(a.severity),
                ),
            ],
          ),
          for (final a in report.weakAreas)
            if (a.evidence.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs + 2,
                  bottom: AppSpacing.sm,
                ),
                child: Text(
                  '${a.title}：${a.evidence.join('；')}',
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: TurnaTheme.textHintColor(context),
                    height: 1.5,
                  ),
                ),
              ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // ── 建议：优先建议（编号行）+ 可练想法 ──
        if (report.priorityTips.isNotEmpty) ...[
          ReportSectionHeading(title: AppStrings.aiDiagnosisSectionAdvice),
          _NumberedLines(lines: report.priorityTips),
          const SizedBox(height: AppSpacing.md),
        ],
        if (report.exampleDrillIdeas.isNotEmpty) ...[
          Text(
            AppStrings.aiDiagnosisDrills,
            style: AppTextStyles.cardTitle(context).copyWith(fontSize: 15),
          ),
          const SizedBox(height: AppSpacing.sm),
          _NumberedLines(lines: report.exampleDrillIdeas),
          const SizedBox(height: AppSpacing.xl),
        ],

        // ── 行动：目录入口 ──
        ReportSectionHeading(title: AppStrings.aiDiagnosisSectionAction),
        DirectoryLinkRow(
          icon: Icons.school_outlined,
          iconTone: TurnaTheme.brandTeal,
          title: AppStrings.aiDiagnosisSecondaryCta,
          onTap: () => showAiPracticeGenerateSheet(
            context,
            source: AiPracticeSource.difficult,
          ),
        ),
        DirectoryLinkRow(
          icon: Icons.bookmark_add_outlined,
          iconTone: TurnaTheme.anatolianClay,
          title: AppStrings.aiSaveExplanation,
          onTap: () async {
            final store = context.read<AiSavedExplanationsStore>();
            await store.save(SavedExplanation(
              id: AiSavedExplanationsStore.newId(),
              title: AppStrings.aiDiagnosisTitle,
              body: report.toPlainText(),
              source: 'diagnosis',
              createdAt: DateTime.now(),
            ));
            if (context.mounted) {
              TurnaSnackBar.maybeShow(context, AppStrings.aiExplanationSaved);
            }
          },
        ),
        DirectoryLinkRow(
          icon: Icons.copy_rounded,
          iconTone: TurnaTheme.brandSky,
          title: AppStrings.aiDepthCopy,
          showDivider: false,
          onTap: () {
            Clipboard.setData(ClipboardData(text: report.toPlainText()));
            TurnaSnackBar.maybeShow(context, AppStrings.aiDepthCopied);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  static String _severityLabel(String severity) => switch (severity) {
        'high' => AppStrings.aiDiagnosisSeverityHigh,
        'medium' => AppStrings.aiDiagnosisSeverityMedium,
        'low' => AppStrings.aiDiagnosisSeverityLow,
        _ => severity,
      };

  static Color? _severityColor(String severity) => switch (severity) {
        'high' => TurnaTheme.error,
        'medium' => TurnaTheme.warning,
        _ => null,
      };
}

/// 编号行：报告建议段的排版（序号淡色左、正文右，无卡无泡）。
class _NumberedLines extends StatelessWidget {
  const _NumberedLines({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSpacing.xl,
                  child: Text(
                    '${i + 1}.',
                    style: AppTextStyles.captionSm(context).copyWith(
                      color: TurnaTheme.textHintColor(context),
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    lines[i],
                    style: AppTextStyles.bodyText(context)
                        .copyWith(fontSize: 15, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
