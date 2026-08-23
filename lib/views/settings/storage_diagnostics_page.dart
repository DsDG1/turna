// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/application/maintenance/storage_maintenance_service.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Plan 1 Phase 3 minimal diagnostics page: a read-only view over
/// [StorageInventoryService] that explains where the Anki-related bytes live
/// (main database, legacy imports/media, official collection, caches, logs),
/// flags orphan media directories, and offers the one destructive action
/// that is always safe — clearing regenerable caches. The final "存储与性能"
/// layout is Plan 2's call; this page is the data contract behind it.
@RoutePage()
class StorageDiagnosticsPage extends StatefulWidget {
  const StorageDiagnosticsPage({super.key, this.scanner});

  /// Test seam: widget tests run under fake-async, where the service's real
  /// file I/O never completes; inject a synchronous scanner there. Production
  /// leaves this null and uses the real service.
  final StorageInventoryService? scanner;

  @override
  State<StorageDiagnosticsPage> createState() => _StorageDiagnosticsPageState();
}

class _StorageDiagnosticsPageState extends State<StorageDiagnosticsPage> {
  Future<StorageInventoryReport>? _scan;

  @override
  void initState() {
    super.initState();
    _scan = (widget.scanner ?? const StorageInventoryService()).scan();
  }

  void _rescan() => setState(() {
        _scan = (widget.scanner ?? const StorageInventoryService()).scan();
      });

  Future<void> _clearCaches() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理可再生成缓存？'),
        content: const Text(
          '仅清理 Anki 预渲染明文缓存与 AI 请求缓存，'
          '课程、卡片和学习进度不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await StorageMaintenanceService().clearRegenerableCaches();
    _rescan();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '存储与性能',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          FutureBuilder<StorageInventoryReport>(
            future: _scan,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _ErrorCard(
                  message: '扫描失败：${snapshot.error}',
                  onRetry: _rescan,
                );
              }
              final report = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryCard(report: report),
                  const SizedBox(height: 16),
                  ..._categoryBlocks(context, report),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _rescan,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重新扫描'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _clearCaches,
                          icon: const Icon(
                            Icons.cleaning_services_outlined,
                            size: 18,
                          ),
                          label: Text(
                              '清理缓存（${_formatBytes(report.safelyReclaimableBytes)}）'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '扫描时间 ${_formatTime(report.scannedAt)}；'
                    '孤儿数据仅报告，需逐项确认后才会清理。',
                    style: TextStyle(
                      fontSize: 11,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _categoryBlocks(
    BuildContext context,
    StorageInventoryReport report,
  ) {
    const categoryTitles = {
      StorageArtifactCategory.mainDatabase: '主数据库',
      StorageArtifactCategory.legacyAnki: 'Anki Legacy',
      StorageArtifactCategory.legacyAnkiMedia: 'Anki Legacy 媒体',
      StorageArtifactCategory.officialAnki: 'Anki Official',
      StorageArtifactCategory.regenerableCache: '可再生成缓存',
      StorageArtifactCategory.logs: '日志',
    };
    return [
      for (final entry in categoryTitles.entries)
        _CategoryCard(
          title: entry.key == StorageArtifactCategory.legacyAnkiMedia
              ? '${entry.value}（${report.mediaDirsByOwner.length} 个导入目录）'
              : entry.value,
          artifacts: report.artifacts
              .where((a) => a.category == entry.key)
              .toList(),
          extra: entry.key == StorageArtifactCategory.mainDatabase
              ? 'WAL ${_formatBytes(report.databaseWalBytes)} · '
                  'SHM ${_formatBytes(report.databaseShmBytes)} · '
                  '可回收空闲页 ${_formatBytes(report.freelistBytes)}'
              : entry.key == StorageArtifactCategory.regenerableCache
                  ? 'AI 缓存条目 ${report.aiCacheEntries}（内存键，不计入字节）'
                  : null,
        ),
    ];
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.report});

  final StorageInventoryReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.brandTeal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sd_storage_outlined,
                  color: TurnaTheme.brandTeal, size: 22),
              const SizedBox(width: 10),
              Text(
                '扫描总计 ${_formatBytes(report.totalPhysicalBytes)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '一键可安全释放 ${_formatBytes(report.safelyReclaimableBytes)}'
            '${report.orphans.isEmpty ? '' : ' · 疑似孤儿 ${report.orphans.length} 项'}',
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.artifacts,
    this.extra,
  });

  final String title;
  final List<StorageArtifactReport> artifacts;
  final String? extra;

  static const _policyLabels = {
    StorageCleanupPolicy.deleteSaga: '随删除流程清理',
    StorageCleanupPolicy.optimize: '可优化',
    StorageCleanupPolicy.safeClear: '可安全清理',
    StorageCleanupPolicy.confirmOnly: '需确认',
  };

  @override
  Widget build(BuildContext context) {
    if (artifacts.isEmpty) {
      return const SizedBox.shrink();
    }
    var bytes = 0;
    for (final a in artifacts) {
      bytes += a.physicalBytes;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
          border: Border.all(
            color: TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Text(
                  _formatBytes(bytes),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
              ],
            ),
            if (extra != null) ...[
              const SizedBox(height: 4),
              Text(
                extra!,
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ],
            const SizedBox(height: 6),
            for (final artifact in artifacts.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (artifact.orphaned)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: TurnaTheme.warning,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${artifact.label} · ${_formatBytes(artifact.physicalBytes)}'
                        '${artifact.fileCount > 0 ? ' · ${artifact.fileCount} 个文件' : ''}'
                        ' · ${_policyLabels[artifact.cleanupPolicy]}',
                        style: TextStyle(
                          fontSize: 12,
                          color: artifact.orphaned
                              ? TurnaTheme.warning
                              : TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (artifacts.length > 12)
              Text(
                '… 以及另外 ${artifacts.length - 12} 项',
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(message,
              style: const TextStyle(color: TurnaTheme.error, fontSize: 13)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} $h:$m';
}
