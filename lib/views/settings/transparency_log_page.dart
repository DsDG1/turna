// Flutter imports:
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Project imports:
import 'package:turna/core/log_capture.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// 透明度报告页 — 隐私详情页底部 pill 跳进来。
///
/// 三段:
///   1. **最近操作日志** — info 级,最多 50 条
///   2. **错误日志** — warn / error / fatal 级,最多 50 条
///   3. **一般数据** — 应用版本、平台、OS、屏幕、语言、时区(一次性读取)
///
/// 数据源:
///   - 1 / 2 段: [LogCapture] 单例,内存 + 本机 JSONL 文件
///   - 3 段:`dart:io` Platform / MediaQuery / package_info_plus / DateTime
///
/// 顶部 hero + 末尾说明 + 复制按钮 + 一键清空,跟隐私详情页风格一致。
@RoutePage()
class TransparencyLogPage extends StatelessWidget {
  const TransparencyLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.transparencyTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        actions: [
          IconButton(
            tooltip: AppStrings.transparencyClearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: TurnaTheme.courseTreeGradientFor(context),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TransparencyHero(),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.transparencyOpsTitle),
              const SizedBox(height: 10),
              const _OpsLogCard(),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.transparencyErrorTitle),
              const SizedBox(height: 10),
              const _ErrorLogCard(),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.transparencyDeviceTitle),
              const SizedBox(height: 10),
              const _DeviceInfoCard(),
              const SizedBox(height: 20),
              const _FooterNote(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.transparencyClearAll),
        content: Text(AppStrings.transparencyFooter),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.commonOk),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LogCapture.instance.clear();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.transparencyClearAllDone),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// 顶部 hero:visibility 图标 + 标题 + 一句话导语 + 复制全部按钮
class _TransparencyHero extends StatelessWidget {
  const _TransparencyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部 teal 装饰条
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  TurnaTheme.brandTeal,
                  TurnaTheme.brandTeal.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusMedium),
                  ),
                  child: const Icon(
                    Icons.visibility_outlined,
                    color: TurnaTheme.brandTeal,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.transparencyTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.transparencyIntro,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 信息级操作日志卡片
class _OpsLogCard extends StatelessWidget {
  const _OpsLogCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LogEntry>>(
      valueListenable: LogCapture.instance.entries,
      builder: (context, all, _) {
        final ops = all.where((e) => e.level == Level.info).take(50).toList();
        return _AboutCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardMetaRow(count: ops.length, kind: _LogKind.info),
              const SizedBox(height: 8),
              if (ops.isEmpty)
                _EmptyLine(text: AppStrings.transparencyOpsEmpty)
              else
                for (final e in ops) _LogLine(entry: e),
            ],
          ),
        );
      },
    );
  }
}

/// 错误级日志卡片
class _ErrorLogCard extends StatelessWidget {
  const _ErrorLogCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LogEntry>>(
      valueListenable: LogCapture.instance.entries,
      builder: (context, all, _) {
        final errs = all
            .where((e) =>
                e.level == Level.warning ||
                e.level == Level.error ||
                e.level == Level.fatal)
            .take(50)
            .toList();
        return _AboutCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardMetaRow(count: errs.length, kind: _LogKind.error),
              const SizedBox(height: 8),
              if (errs.isEmpty)
                _EmptyLine(text: AppStrings.transparencyErrorEmpty)
              else
                for (final e in errs) _LogLine(entry: e),
            ],
          ),
        );
      },
    );
  }
}

/// 一次性读本机信息卡片
class _DeviceInfoCard extends StatefulWidget {
  const _DeviceInfoCard();

  @override
  State<_DeviceInfoCard> createState() => _DeviceInfoCardState();
}

class _DeviceInfoCardState extends State<_DeviceInfoCard> {
  PackageInfo? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    PackageInfo? info;
    try {
      info = await PackageInfo.fromPlatform();
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width.toStringAsFixed(0);
    final screenH = mq.size.height.toStringAsFixed(0);
    final dpr = mq.devicePixelRatio.toStringAsFixed(2);
    final screenLabel = '$screenW×$screenH · DPR $dpr';

    final osLabel = _osLabel();
    final localeLabel = _localeLabel();
    final tzLabel = DateTime.now().timeZoneName;
    final versionLabel = _loading
        ? '…'
        : (_info == null
            ? '—'
            : '${_info!.version} (${_info!.buildNumber})');

    final rows = <_DeviceRow>[
      _DeviceRow(
        icon: Icons.tag_rounded,
        title: AppStrings.transparencyDeviceAppVersion,
        value: versionLabel,
      ),
      _DeviceRow(
        icon: Icons.devices_rounded,
        title: AppStrings.transparencyDevicePlatform,
        value: _platformLabel(),
      ),
      _DeviceRow(
        icon: Icons.memory_rounded,
        title: AppStrings.transparencyDeviceOs,
        value: osLabel,
      ),
      _DeviceRow(
        icon: Icons.aspect_ratio_rounded,
        title: AppStrings.transparencyDeviceScreen,
        value: screenLabel,
      ),
      _DeviceRow(
        icon: Icons.translate_rounded,
        title: AppStrings.transparencyDeviceLocale,
        value: localeLabel,
      ),
      _DeviceRow(
        icon: Icons.schedule_rounded,
        title: AppStrings.transparencyDeviceTimezone,
        value: tzLabel,
      ),
    ];

    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.transparencyDeviceIntro,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Divider(
                  height: 1,
                  color: TurnaTheme.statCardBorder(context),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _platformLabel() {
    try {
      return '${Platform.operatingSystem} (${Platform.operatingSystemVersion.split(' ').first})';
    } catch (_) {
      return '—';
    }
  }

  String _osLabel() {
    try {
      final v = Platform.operatingSystemVersion;
      if (v.isEmpty) return Platform.operatingSystem;
      return v;
    } catch (_) {
      return '—';
    }
  }

  String _localeLabel() {
    try {
      final code = Platform.localeName;
      return code.isEmpty ? '—' : code;
    } catch (_) {
      return '—';
    }
  }
}

/// 末尾说明 + 复制全部 + 本机文件路径
class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.brandTeal.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: TurnaTheme.brandTeal,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.transparencyFooter,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                        height: 1.5,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<List<LogEntry>>(
            valueListenable: LogCapture.instance.entries,
            builder: (context, _, __) {
              final file = LogCapture.instance.fileForDisplay;
              if (file == null) return const SizedBox.shrink();
              return Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: TurnaTheme.brandTeal,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${AppStrings.transparencyLogFileLabel}: ${file.path}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '复制路径',
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: TurnaTheme.brandTeal,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: file.path),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 卡片标题行(数量徽标)
class _CardMetaRow extends StatelessWidget {
  final int count;
  final _LogKind kind;

  const _CardMetaRow({required this.count, required this.kind});

  @override
  Widget build(BuildContext context) {
    final color = kind == _LogKind.error
        ? const Color(0xFFC62828)
        : TurnaTheme.brandTeal;
    final label = kind == _LogKind.error
        ? AppStrings.transparencyErrorTitle
        : AppStrings.transparencyOpsTitle;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          ),
          child: Text(
            AppStrings.transparencyLogCount(count),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
      ],
    );
  }
}

/// 一行日志(时间 + 等级 + 消息)。有 stack trace 的可点击展开。
class _LogLine extends StatefulWidget {
  final LogEntry entry;

  const _LogLine({required this.entry});

  @override
  State<_LogLine> createState() => _LogLineState();
}

class _LogLineState extends State<_LogLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final hh = entry.timestamp.hour.toString().padLeft(2, '0');
    final mm = entry.timestamp.minute.toString().padLeft(2, '0');
    final ss = entry.timestamp.second.toString().padLeft(2, '0');
    final time = '$hh:$mm:$ss';

    final color = entry.isAbnormal
        ? const Color(0xFFC62828)
        : TurnaTheme.textHintColor(context);
    final levelTag = entry.isAbnormal
        ? (entry.level == Level.warning
            ? AppStrings.transparencyLevelWarn
            : AppStrings.transparencyLevelError)
        : AppStrings.transparencyLevelInfo;
    final expandable = entry.hasStackTrace;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: expandable
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        time,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: TurnaTheme.textHintColor(context),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        levelTag,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.displayMessage,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: TurnaTheme.textSecondaryColor(context),
                              height: 1.4,
                            ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (expandable)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 1),
                        child: Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: TurnaTheme.textHintColor(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (expandable && _expanded)
            Container(
              margin:
                  const EdgeInsets.only(left: 70, top: 2, bottom: 4, right: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: TurnaTheme.statCardBorder(context),
                ),
              ),
              child: SelectableText(
                entry.stackTrace!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;

  const _EmptyLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 16,
            color: TurnaTheme.brandTeal,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DeviceRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: TurnaTheme.brandTeal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.textPrimaryColor(context),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 短 teal 横条 + 小标题
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// 通用内容卡片
class _AboutCard extends StatelessWidget {
  final Widget child;

  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: child,
    );
  }
}

enum _LogKind { info, error }
