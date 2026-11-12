// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/performance_trace.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// System health page — always freely dismissible (Plan §15).
///
/// Ordinary log-derived alerts never trap the user here: they surface as a
/// non-blocking banner the user can acknowledge (acknowledging hides the
/// banner; it does NOT change the underlying facts — only a passing
/// self-check can mark the event resolved). The dedicated data-integrity
/// hazard shows a strong warning and points at backup / export / safe mode,
/// but still does not lock the page.
@RoutePage()
class SystemHealthPage extends StatelessWidget {
  const SystemHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<SystemHealthMonitor>();
    final event = monitor.event;
    return SettingsScaffold(
      title: AppStrings.systemHealthTitle,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
        children: [
          if (monitor.hasDataIntegrityBlock) ...[
            _DataIntegrityBanner(
              reason: monitor.dataIntegrityReason,
            ),
            const SizedBox(height: 12),
          ] else if (monitor.hasUnacknowledgedAlert) ...[
            _UnacknowledgedBanner(
              monitor: monitor,
              score: monitor.score,
            ),
            const SizedBox(height: 12),
          ],
          _HealthSummary(monitor: monitor),
          const SizedBox(height: 20),
          SettingsSectionTitle(
            icon: Icons.list_alt_rounded,
            title: AppStrings.systemHealthTopIssues,
          ),
          const SizedBox(height: 8),
          if (event.topGroups.isEmpty)
            SettingsEmptyCard(
              message: AppStrings.systemHealthAllClear,
            )
          else
            SettingsCard(
              children: [
                for (var i = 0; i < event.topGroups.length; i++) ...[
                  if (i > 0) settingsTileDivider(context),
                  _HealthGroupTile(group: event.topGroups[i]),
                ],
              ],
            ),
          const SizedBox(height: 20),
          SettingsSectionTitle(
            icon: Icons.handyman_outlined,
            title: AppStrings.systemHealthActions,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsActionTile(
                icon: Icons.refresh_rounded,
                title: AppStrings.systemHealthRunSelfCheck,
                subtitle: monitor.resolved
                    ? AppStrings.systemHealthRunSelfCheckDoneSubtitle
                    : AppStrings.systemHealthRunSelfCheckSubtitle,
                onTap: (context) => _runSelfCheck(context, monitor),
              ),
              settingsTileDivider(context),
              if (monitor.hasUnacknowledgedAlert) ...[
                SettingsActionTile(
                  icon: Icons.visibility_outlined,
                  title: AppStrings.systemHealthAcknowledge,
                  subtitle: AppStrings.systemHealthAcknowledgeSubtitle,
                  onTap: (context) => monitor.acknowledge(),
                ),
                settingsTileDivider(context),
              ],
              SettingsActionTile(
                icon: Icons.health_and_safety_outlined,
                title: AppStrings.systemHealthAdviceTitle,
                subtitle: AppStrings.systemHealthAdviceSubtitle,
                onTap: (context) => _showAdvice(context, event),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.ios_share_rounded,
                title: AppStrings.systemHealthExportReport,
                subtitle: AppStrings.systemHealthExportReportSubtitle,
                onTap: (context) => _previewReport(context, monitor),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.copy_all_rounded,
                title: AppStrings.systemHealthCopySummary,
                subtitle: AppStrings.systemHealthCopySummarySubtitle,
                onTap: (context) => _copyReport(context, monitor),
              ),
              settingsTileDivider(context),
              SettingsSwitchTile(
                icon: Icons.shield_outlined,
                title: AppStrings.systemHealthSafeMode,
                subtitle: AppStrings.systemHealthSafeModeSubtitle,
                value: monitor.safeMode,
                onChanged: monitor.setSafeMode,
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.article_outlined,
                title: AppStrings.systemHealthViewRawLogs,
                subtitle: AppStrings.systemHealthViewRawLogsSubtitle,
                onTap: (context) =>
                    context.router.push(const TransparencyLogRoute()),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.delete_sweep_outlined,
                title: AppStrings.systemHealthClearLogs,
                subtitle: AppStrings.systemHealthClearLogsSubtitle,
                onTap: (context) => _clearLogs(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runSelfCheck(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final passed = await monitor.runSelfCheck();
    if (!context.mounted) return;
    TurnaSnackBar.showVia(
      messenger,
      context,
      passed
          ? AppStrings.systemHealthSelfCheckPassed
          : AppStrings.systemHealthSelfCheckFailed,
    );
  }

  Future<void> _clearLogs(BuildContext context) async {
    // R18 全局弹层：清日志是破坏性操作，确认走全局确认弹层。
    final confirmed = await showTurnaConfirmDialog(
      context: context,
      title: AppStrings.systemHealthClearLogsTitle,
      message: AppStrings.systemHealthClearLogsMessage,
      confirmLabel: AppStrings.systemHealthClearLogs,
      destructive: true,
    );
    if (confirmed == true) await LogCapture.instance.clear();
  }

  void _showAdvice(BuildContext context, SystemHealthEvent event) {
    final modules = event.groups.values.map((item) => item.module).toSet();
    final advice = <String>[
      if (modules.contains('数据库')) AppStrings.systemHealthAdviceDb,
      if (modules.contains('记忆卡渲染') || modules.contains('WebView'))
        AppStrings.systemHealthAdviceAnki,
      if (modules.contains('TTS / 音频')) AppStrings.systemHealthAdviceTts,
      if (modules.contains('AI 网络')) AppStrings.systemHealthAdviceAi,
      if (modules.contains('课程加载')) AppStrings.systemHealthAdviceCourse,
      if (modules.isEmpty) AppStrings.systemHealthAdviceNone,
    ];
    showDialog<void>(
      context: context,
      builder: (context) => SettingsInfoDialog(
        title: AppStrings.systemHealthAdviceDialogTitle,
        message: advice.join('\n\n'),
      ),
    );
  }

  Future<void> _previewReport(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final report = await _buildReport(context, monitor);
    if (!context.mounted) return;
    // R18 全局弹层：报告预览走全局弹层（可滚动正文 + 操作区）。
    final export = await showTurnaSheet<bool>(
      context: context,
      title: AppStrings.systemHealthReportPreviewTitle,
      isScrollControlled: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SingleChildScrollView(child: SelectableText(report)),
      ),
      actions: [
        TurnaSheetAction(
          label: AppStrings.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        TurnaSheetAction(
          label: AppStrings.systemHealthExportAction,
          primary: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (export != true) return;
    await Share.shareXFiles(
      [
        XFile.fromData(
          utf8.encode(report),
          mimeType: 'text/plain',
          name: 'turna_diagnostic_report.txt',
        ),
      ],
      subject: 'Turna 脱敏诊断报告',
    );
  }

  Future<void> _copyReport(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final report = await _buildReport(context, monitor);
    await Clipboard.setData(ClipboardData(text: report));
    if (context.mounted) {
      TurnaSnackBar.maybeShow(context, AppStrings.systemHealthReportCopied);
    }
  }

  Future<String> _buildReport(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final settings = context.read<SettingsProvider>();
    final event = monitor.event;
    final schemaVersion = getIt.isRegistered<ICourseRepository>()
        ? getIt<ICourseRepository>().schemaVersion
        : -1;
    var ttsStatus = '未检查';
    if (getIt.isRegistered<TtsAvailabilityChecker>()) {
      try {
        final lang = getIt.isRegistered<LanguageProvider>()
            ? getIt<LanguageProvider>().ttsLanguageCode
            : LanguageCodes.turkish;
        final tts = await getIt<TtsAvailabilityChecker>().diagnose(lang);
        ttsStatus = tts.preferredStatus.name;
      } catch (_) {
        ttsStatus = '检查失败';
      }
    }
    final lines = <String>[
      'Turna 脱敏诊断报告',
      '事件：${event.id}',
      '当前应用版本：${monitor.currentAppVersion}',
      '事件创建版本：${event.appVersion}',
      '数据结构版本：${schemaVersion < 0 ? '未知' : schemaVersion}',
      '平台：${kIsWeb ? 'web' : defaultTargetPlatform.name}',
      'WebView：${kIsWeb ? 'web' : defaultTargetPlatform.name}',
      'TTS：$ttsStatus',
      '健康等级：${monitor.level.name}',
      '活跃评分：${monitor.score}',
      '已确认：${monitor.acknowledged}',
      '自检通过：${event.checkPassed}',
      '已解决：${monitor.resolved}',
      '安全模式：${event.safeMode}',
      '数据完整性风险：${monitor.hasDataIntegrityBlock ? '是（${monitor.dataIntegrityReason}）' : '否'}',
      '强制禁用 JS：${settings.ankiForceDisableJs}',
      '',
      '错误摘要：',
      for (final indexed in event.groups.values.indexed)
        '- 问题组 ${indexed.$1 + 1} [${indexed.$2.level}] '
            '${indexed.$2.module} ×${indexed.$2.count}（原始正文已省略）',
      '',
      PerformanceTrace.instance.summary(),
      '',
      '已自动排除：API 密钥、认证信息、完整卡片正文、AI 对话正文和个人路径。',
    ];
    return SystemHealthMonitor.redact(lines.join('\n'));
  }
}

/// Non-blocking banner for an unacknowledged attention/critical alert. The
/// user can leave this page at any time; acknowledging only hides the
/// banner until the next detection.
class _UnacknowledgedBanner extends StatelessWidget {
  const _UnacknowledgedBanner({required this.monitor, required this.score});

  final SystemHealthMonitor monitor;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SettingsInfoCard(
        icon: Icons.notification_important_rounded,
        tone: score >= SystemHealthMonitor.alertThreshold
            ? SettingsInfoTone.danger
            : SettingsInfoTone.warning,
        text: AppStrings.systemHealthAlertBanner(score),
      ),
    );
  }
}

/// Strong warning for the dedicated data-integrity hazard. Even here the
/// page is not locked — the user is pointed at backup/export/safe-mode
/// instead of being trapped (Plan §15.3 "data-integrity blocking").
class _DataIntegrityBanner extends StatelessWidget {
  const _DataIntegrityBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SettingsInfoCard(
        icon: Icons.report_rounded,
        tone: SettingsInfoTone.danger,
        text: AppStrings.systemHealthIntegrityBanner(reason),
      ),
    );
  }
}

/// 等级开篇（湿地雾光 R17）：报告构图的指标头 —— 健康等级为大数字，
/// 语义色按等级取（正常 success / 需注意 warning / 严重 error）。
class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.monitor});
  final SystemHealthMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final event = monitor.event;
    final (color, label) = switch (monitor.level) {
      SystemHealthLevel.normal => (
          TurnaTheme.success,
          monitor.resolved
              ? AppStrings.systemHealthLevelNormalChecked
              : AppStrings.systemHealthLevelNormal
        ),
      SystemHealthLevel.attention => (
          TurnaTheme.warning,
          AppStrings.systemHealthLevelAttention
        ),
      SystemHealthLevel.critical => (
          TurnaTheme.error,
          AppStrings.systemHealthLevelCritical
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ReportMetricHeader(
        // 页面标题已是「系统健康」，指标头标签用等级语义，避免同名双标题。
        label: AppStrings.systemHealthLevelLabel,
        value: label,
        caption: AppStrings.systemHealthScoreSummary(
          monitor.score,
          event.groups.length,
        ),
        accentColor: color,
      ),
    );
  }
}

/// Per-group row in the "主要问题" card. Uses the severity color for both
/// the icon and the icon-container tint, so the user can scan the list
/// and immediately see fatal/error vs warning.
class _HealthGroupTile extends StatelessWidget {
  const _HealthGroupTile({required this.group});

  final SystemHealthErrorGroup group;

  @override
  Widget build(BuildContext context) {
    final isError = group.level == 'fatal' || group.level == 'error';
    final color = isError ? TurnaTheme.error : TurnaTheme.warning;
    final icon = isError ? Icons.error_outline : Icons.warning_amber_rounded;
    return SettingsTile(
      icon: icon,
      iconColor: color,
      iconBackground: color.withValues(alpha: 0.10),
      title: '${group.module} · ${group.level}',
      subtitle: AppStrings.systemHealthGroupSubtitle(
        group.message,
        group.count,
        group.ongoing
            ? AppStrings.systemHealthGroupOngoing
            : AppStrings.systemHealthGroupStopped,
      ),
    );
  }
}
