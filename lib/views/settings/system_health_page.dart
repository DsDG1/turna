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
      title: '系统健康',
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
                icon: Icons.refresh_rounded,
                title: '运行自检',
                subtitle: monitor.resolved
                    ? '上次自检已通过，当前无活跃告警'
                    : '检查数据库完整性并重新计算健康状态；自检通过且无新异常才会标记为已解决',
                onTap: (context) => _runSelfCheck(context, monitor),
              ),
              settingsTileDivider(context),
              if (monitor.hasUnacknowledgedAlert) ...[
                SettingsActionTile(
                  icon: Icons.visibility_outlined,
                  title: '我知道了',
                  subtitle: '隐藏提示横幅；不影响故障事实，新异常会重新提示',
                  onTap: (context) => monitor.acknowledge(),
                ),
                settingsTileDivider(context),
              ],
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
    );
  }

  Future<void> _runSelfCheck(
    BuildContext context,
    SystemHealthMonitor monitor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final passed = await monitor.runSelfCheck();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(passed
            ? '自检通过：数据库完整性正常，且活跃窗口内无未衰减的严重异常。'
            : '自检未完全通过：请查看主要问题列表，或导出诊断报告反馈。'),
      ),
    );
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
      if (modules.contains('数据库')) '数据库：先运行自检检查数据库完整性；不要清除学习记录。',
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
      '健康等级：${monitor.level.name}',
      '活跃评分：${monitor.score}',
      '已确认：${monitor.acknowledged}',
      '自检通过：${event.checkPassed}',
      '已解决：${monitor.resolved}',
      '安全模式：${event.safeMode}',
      '数据完整性风险：${monitor.hasDataIntegrityBlock ? '是（${monitor.dataIntegrityReason}）' : '否'}',
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
        text: '检测到异常（活跃评分 $score）。本提示不会阻止你继续使用应用；'
            '运行自检通过且异常停止复发后会自动标记为已解决。',
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
        text: '检测到数据完整性风险：$reason\n'
            '建议先导出备份与诊断报告，再运行自检。写入类操作请谨慎；'
            '你可以随时离开本页。',
      ),
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({required this.monitor});
  final SystemHealthMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final event = monitor.event;
    final (color, icon, label) = switch (monitor.level) {
      SystemHealthLevel.normal => (
          monitor.resolved ? TurnaTheme.success : TurnaTheme.success,
          Icons.check_circle,
          monitor.resolved ? '正常（自检通过）' : '正常'
        ),
      SystemHealthLevel.attention => (
          TurnaTheme.warning,
          Icons.warning_rounded,
          '需要注意'
        ),
      SystemHealthLevel.critical => (TurnaTheme.error, Icons.error, '严重'),
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
                Text('活跃评分 ${monitor.score} · ${event.groups.length} 个问题组'),
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
      subtitle:
          '${group.message}\n发生 ${group.count} 次 · ${group.ongoing ? '仍在持续' : '目前已停止'}',
    );
  }
}
