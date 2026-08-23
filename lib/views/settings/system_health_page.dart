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
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Registered with auto_route so the app shell can push it via
/// `router.push(const SystemHealthRoute())` and detect the top of the
/// stack by name. The page is also wrapped in a [PopScope] that blocks
/// leaving until the active alert is marked handled — a critical-alert
/// monitor state must not be silently dismissed.
@RoutePage()
class SystemHealthPage extends StatelessWidget {
  const SystemHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<SystemHealthMonitor>();
    final event = monitor.event;
    final canLeave = !monitor.isScoreExceeded && !monitor.hasActiveAlert;
    return PopScope(
      // While a critical or attention alert is still unhandled, the user
      // must stay on this page so they actually see and resolve the issue
      // instead of bouncing back to whatever they were doing and ignoring
      // it. The hard-stop is by design: an unresolved system-health alert
      // can mask data corruption or render loop bugs.
      canPop: canLeave,
      child: SettingsScaffold(
        title: '系统健康',
        allowPop: canLeave,
        actions: [
          if (monitor.isScoreExceeded || monitor.hasActiveAlert)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => _confirmAndDeduct(context, monitor),
                icon: const Icon(
                  Icons.done_all_rounded,
                  color: TurnaTheme.brandTeal,
                ),
                label: const Text(
                  '确定（-40分）',
                  style: TextStyle(
                    color: TurnaTheme.brandTeal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
        body: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          children: [
            if (monitor.isScoreExceeded || monitor.hasActiveAlert) ...[
              _ForcedStayBanner(score: event.score),
              const SizedBox(height: 12),
            ],
            _HealthSummary(event: event),
            const SizedBox(height: 20),
            const SettingsSectionTitle(
              icon: Icons.list_alt_rounded,
              title: '主要问题',
            ),
            const SizedBox(height: 8),
            if (event.topGroups.isEmpty)
              const SettingsEmptyCard(
                icon: Icons.check_circle_outline,
                message: '当前系统运行良好，没有需要处理的异常组',
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
            const SettingsSectionTitle(
              icon: Icons.handyman_outlined,
              title: '处理操作',
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsActionTile(
                  icon: Icons.health_and_safety_outlined,
                  title: '查看诊断建议',
                  subtitle: '按数据库、课程、Anki、WebView、TTS 和 AI 网络归类',
                  onTap: (context) => _showAdvice(context, event),
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.ios_share_rounded,
                  title: '导出脱敏诊断报告',
                  subtitle: '先预览；自动排除密钥、正文、对话和个人路径',
                  onTap: (context) => _previewReport(context, monitor),
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.copy_all_rounded,
                  title: '复制诊断摘要',
                  subtitle: '包含脱敏的性能 P50/P95 与慢操作 Top-N',
                  onTap: (context) => _copyReport(context, monitor),
                ),
                settingsTileDivider(context),
                SettingsSwitchTile(
                  icon: Icons.shield_outlined,
                  title: '安全模式',
                  subtitle: '临时禁用模板 JS、外部网络和高风险后台能力；不改学习数据',
                  value: monitor.safeMode,
                  onChanged: monitor.setSafeMode,
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.done_all_rounded,
                  title: '确定处理（降低40分）',
                  subtitle:
                      '当前评分 ${monitor.score} 分；确定后降低 40 分（不低于 0 分），降至 40 分以下即可离开',
                  onTap: (context) => _confirmAndDeduct(context, monitor),
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.article_outlined,
                  title: '查看原始日志',
                  subtitle: '打开透明度报告页',
                  onTap: (context) =>
                      context.router.push(const TransparencyLogRoute()),
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.delete_sweep_outlined,
                  title: '清空日志',
                  subtitle: '不会自动把健康状态改为正常，也不会删除学习数据',
                  onTap: (context) => _clearLogs(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeduct(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final current = monitor.score;
    final target = (current - 40).clamp(0, 999999);
    final willResolve = target < SystemHealthMonitor.alertThreshold;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SettingsConfirmDialog(
        title: '确认处理异常并降低 40 分？',
        message: '当前异常评分：$current 分\n'
            '处理后评分：$target 分\n\n'
            '${willResolve ? '评分将降至 40 分以下，确定后即可恢复正常操作。' : '处理后仍有 $target 分（>= 40 分），需继续处理直至低于 40 分。'}',
        confirmText: '确定（-40分）',
      ),
    );
    if (confirmed != true) return;
    await monitor.confirmAndDeductScore(40);
    if (context.mounted && monitor.score < SystemHealthMonitor.alertThreshold) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _clearLogs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const SettingsConfirmDialog(
        title: '清空本机日志？',
        message: '日志会被删除，但当前告警仍会保留；这不代表故障已解决。',
        confirmText: '清空',
      ),
    );
    if (confirmed == true) await LogCapture.instance.clear();
  }

  void _showAdvice(BuildContext context, SystemHealthEvent event) {
    final modules = event.groups.values.map((item) => item.module).toSet();
    final advice = <String>[
      if (modules.contains('数据库')) '数据库：先检查数据库完整性；不要清除学习记录。',
      if (modules.contains('Anki 渲染') || modules.contains('WebView'))
        'Anki / WebView：启用安全模式或将相关牌组改为纯文本兼容。',
      if (modules.contains('TTS / 音频')) 'TTS / 音频：检查系统语音引擎和媒体文件是否可用。',
      if (modules.contains('AI 网络')) 'AI 网络：检查服务地址与网络，不要在报告中粘贴 API 密钥。',
      if (modules.contains('课程加载')) '课程加载：返回课程管理页检查导入状态；诊断不会修改排程。',
      if (modules.isEmpty) '当前没有需要处理的问题。',
    ];
    showDialog<void>(
      context: context,
      builder: (context) => SettingsInfoDialog(
        title: '只读诊断建议',
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
    final export = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        ),
        title: const Text('诊断报告预览'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppStrings.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '导出',
              style: TextStyle(color: TurnaTheme.brandTeal),
            ),
          ),
        ],
      ),
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('已复制脱敏诊断摘要')),
      );
    }
  }

  Future<String> _buildReport(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final settings = context.read<SettingsProvider>();
    final event = monitor.event;
    final schemaVersion = getIt.isRegistered<CourseDatabase>()
        ? getIt<CourseDatabase>().schemaVersion
        : -1;
    var ttsStatus = '未检查';
    if (getIt.isRegistered<TtsAvailabilityChecker>()) {
      try {
        final tts = await getIt<TtsAvailabilityChecker>().diagnose('tr');
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
      '健康等级：${event.level.name}',
      '异常评分：${event.score}',
      '安全模式：${event.safeMode}',
      '预渲染缓存：${settings.ankiPreRenderEnabled}',
      '强制禁用 JS：${settings.ankiForceDisableJs}',
      'Lite 阈值：${settings.ankiLiteThreshold}',
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

/// Top-of-body strip that explains why the user can't leave this page yet.
/// Pure presentational; the actual blocking happens in [PopScope] above and
/// in `_AppShellState._onHealthChanged` in app.dart, which both key off
/// [SystemHealthMonitor.hasActiveAlert].
class _ForcedStayBanner extends StatelessWidget {
  const _ForcedStayBanner({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return SettingsInfoCard(
      icon: Icons.lock_outline,
      tone: SettingsInfoTone.danger,
      text: '系统健康异常评分达到 $score 分（已达到或超过 40 分阈值），已打断当前操作并强制停留在此页。'
          '点击右上角「确定（-40分）」确认后将扣减 40 分（不低于 0 分），降至 40 分以下即可离开。',
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.event});
  final SystemHealthEvent event;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (event.level) {
      SystemHealthLevel.normal => (
          TurnaTheme.success,
          Icons.check_circle,
          '正常'
        ),
      SystemHealthLevel.attention => (
          TurnaTheme.warning,
          Icons.warning_rounded,
          '需要注意'
        ),
      SystemHealthLevel.critical => (
          TurnaTheme.error,
          Icons.error_rounded,
          '严重'
        ),
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: color)),
                Text('异常评分 ${event.score} · ${event.groups.length} 个问题组'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-group row in the "主要问题" card. Uses the severity color for both
/// the icon and the icon-container tint, so the user can scan the list
/// and immediately see fatal/error vs warning.
class _HealthGroupTile extends StatelessWidget {
  const _HealthGroupTile({required this.group});

  final dynamic
      group; // SystemHealthGroup — kept loose to avoid an import cycle.

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
      subtitle:
          '${group.message}\n发生 ${group.count} 次 · ${group.ongoing ? '仍在持续' : '目前已停止'}',
    );
  }
}
