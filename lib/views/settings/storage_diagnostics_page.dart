// Dart imports:
import 'dart:math' as math;

// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/diagnostics/cache_diagnostics_registry.dart';
import 'package:turna/application/diagnostics/runtime_memory_snapshot.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/application/maintenance/storage_maintenance_service.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// User-facing storage overview ("存储与性能"): a dashboard over
/// [StorageInventoryService] that shows total usage with a share ring, four
/// plain-language category cards, leftover-file warnings, and the one safe
/// action — clearing regenerable caches.
///
/// Low-level diagnostics (write telemetry, cache entry counts, WAL/SHM/free
/// pages) are intentionally NOT shown here; the underlying services still
/// exist for the developer-facing diagnostics surfaces.
@RoutePage()
class StorageDiagnosticsPage extends StatefulWidget {
  const StorageDiagnosticsPage({
    super.key,
    this.scanner,
    this.cacheRegistry,
    this.memorySampler,
  });

  /// Test seam: widget tests run under fake-async, where the service's real
  /// file I/O never completes; inject a synchronous scanner there. Production
  /// leaves this null and uses the real service.
  final StorageInventoryService? scanner;
  final CacheDiagnosticsRegistry? cacheRegistry;
  final Future<RuntimeMemorySnapshot> Function()? memorySampler;

  @override
  State<StorageDiagnosticsPage> createState() => _StorageDiagnosticsPageState();
}

/// One loaded page state: the disk inventory plus a runtime memory sample.
class _PageData {
  const _PageData({required this.report, this.memory});

  final StorageInventoryReport report;
  final RuntimeMemorySnapshot? memory;
}

class _StorageDiagnosticsPageState extends State<StorageDiagnosticsPage> {
  late final CacheDiagnosticsRegistry _cacheRegistry;

  /// The last successfully loaded data, kept on screen while a rescan runs
  /// so the page never flashes back to a full-screen spinner.
  _PageData? _data;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _cacheRegistry =
        widget.cacheRegistry ?? CacheDiagnosticsRegistry.production();
    _rescan();
  }

  Future<void> _rescan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        (widget.scanner ?? const StorageInventoryService()).scan(),
        (widget.memorySampler ?? RuntimeMemorySnapshot.sample)(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _PageData(
          report: results[0] as StorageInventoryReport,
          memory: results[1] as RuntimeMemorySnapshot,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _clearCaches(int reclaimableBytes) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存？'),
        content: Text(
          '将清理临时缓存（约 ${_formatBytes(reclaimableBytes)}）。'
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
    await _cacheRegistry.clearRegenerable();
    await _rescan();
  }

  /// Delete leftover media directories through the unified uninstall saga —
  /// it also drops any orphaned import rows the interrupted uninstall left
  /// behind. Locked files stay on disk and are retried on the next start.
  Future<void> _deleteOrphans(
    List<StorageArtifactReport> orphans,
    int bytes,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除残留文件？'),
        content: Text(
          '将删除 ${orphans.length} 个无主残留文件夹（约 ${_formatBytes(bytes)}）。'
          '它们不属于任何课程，删除不影响现有学习数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    var cleaned = 0;
    for (final orphan in orphans) {
      try {
        if (await getIt<AnkiDeckManager>().uninstall(orphan.ownerId)) {
          cleaned++;
        }
      } catch (e) {
        debugPrint('[StorageDiagnostics] orphan delete failed '
            'for ${orphan.ownerId}: $e');
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清理 $cleaned/${orphans.length} 个残留文件夹')),
    );
    await _rescan();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '存储与性能',
      actions: [
        IconButton(
          onPressed: _loading ? null : _rescan,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: '重新扫描',
        ),
      ],
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_error != null) {
        return _ErrorCard(
          message: '扫描失败：$_error',
          onRetry: _rescan,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final report = data.report;
    final reclaimable = report.safelyReclaimableBytes;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SizedBox(
          height: 3,
          child: _loading ? const LinearProgressIndicator() : null,
        ),
        const SizedBox(height: 8),
        _TotalCard(report: report),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: reclaimable > 0 ? () => _clearCaches(reclaimable) : null,
            icon: Icon(
              reclaimable > 0
                  ? Icons.cleaning_services_outlined
                  : Icons.check_circle_outline,
              size: 18,
            ),
            label: Text(
              reclaimable > 0
                  ? '清理缓存，可释放 ${_formatBytes(reclaimable)}'
                  : '缓存很干净，无需清理',
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CategoryGrid(report: report),
        if (report.orphans.isNotEmpty) ...[
          const SizedBox(height: 16),
          _OrphanWarningCard(
            orphans: report.orphans,
            onDelete: () => _deleteOrphans(
              report.orphans,
              report.orphans.fold<int>(0, (sum, a) => sum + a.physicalBytes),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _MemoryCard(snapshot: data.memory),
        const SizedBox(height: 12),
        Text(
          '扫描于 ${_formatTime(report.scannedAt)}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: TurnaTheme.textHintColor(context),
          ),
        ),
      ],
    );
  }
}

/// Dashboard hero: large total-usage figure plus a static share ring broken
/// down by the four user-facing categories.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.report});

  final StorageInventoryReport report;

  @override
  Widget build(BuildContext context) {
    final segments = _categorySegments(context, report);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.textHintColor(context).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '总占用',
                  style: TextStyle(
                    fontSize: 13,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatBytes(report.totalPhysicalBytes),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '其中 ${_formatBytes(report.safelyReclaimableBytes)} 可安全释放',
                  style: TextStyle(
                    fontSize: 12,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 104,
            height: 104,
            child: CustomPaint(
              painter: _ShareRingPainter(
                segments: segments,
                trackColor: TurnaTheme.dividerBg(context),
              ),
              child: Center(
                child: Icon(
                  Icons.sd_storage_outlined,
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.7),
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySpec {
  const _CategorySpec({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bytes,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int bytes;
}

int _bytesOf(StorageInventoryReport report, Set<StorageArtifactCategory> cats) {
  var sum = 0;
  for (final a in report.artifacts) {
    if (cats.contains(a.category)) sum += a.physicalBytes;
  }
  return sum;
}

/// The four plain-language buckets every disk byte is folded into. Colors are
/// shared by the category cards and the share ring so they read as one map.
List<_CategorySpec> _categorySpecs(
  BuildContext context,
  StorageInventoryReport report,
) {
  return [
    _CategorySpec(
      title: '学习数据',
      subtitle: '课程与复习进度',
      icon: Icons.school_outlined,
      color: TurnaTheme.brandTeal,
      bytes: _bytesOf(report, const {
        StorageArtifactCategory.mainDatabase,
        StorageArtifactCategory.legacyAnki,
      }),
    ),
    _CategorySpec(
      title: '媒体文件',
      subtitle: '导入的图片与音频',
      icon: Icons.perm_media_outlined,
      color: TurnaTheme.brandSky,
      bytes: _bytesOf(report, const {
        StorageArtifactCategory.legacyAnkiMedia,
      }),
    ),
    _CategorySpec(
      title: 'Anki 收藏',
      subtitle: '官方牌组内容',
      icon: Icons.style_outlined,
      color: TurnaTheme.anatolianClay,
      bytes: _bytesOf(report, const {
        StorageArtifactCategory.officialAnki,
      }),
    ),
    _CategorySpec(
      title: '缓存与日志',
      subtitle: '可随时清理，不影响学习数据',
      icon: Icons.cleaning_services_outlined,
      color: TurnaTheme.textHintColor(context),
      bytes: _bytesOf(report, const {
        StorageArtifactCategory.regenerableCache,
        StorageArtifactCategory.logs,
      }),
    ),
  ];
}

List<({double value, Color color})> _categorySegments(
  BuildContext context,
  StorageInventoryReport report,
) {
  return [
    for (final spec in _categorySpecs(context, report))
      (value: spec.bytes.toDouble(), color: spec.color),
  ];
}

/// 2×2 grid on phones that widens to four columns on wide windows. Built
/// with Wrap instead of a nested GridView so 200% text scale can grow the
/// cards vertically instead of overflowing a fixed aspect ratio.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.report});

  final StorageInventoryReport report;

  static const double _spacing = 12;

  @override
  Widget build(BuildContext context) {
    final specs = _categorySpecs(context, report);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        final width =
            (constraints.maxWidth - _spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final spec in specs)
              SizedBox(width: width, child: _CategoryCard(spec: spec)),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.spec});

  final _CategorySpec spec;

  @override
  Widget build(BuildContext context) {
    final empty = spec.bytes <= 0;
    return Container(
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
              Icon(spec.icon, size: 18, color: spec.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  spec.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatBytes(spec.bytes),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: empty
                  ? TurnaTheme.textHintColor(context)
                  : TurnaTheme.brandTeal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            spec.subtitle,
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Leftover ("orphan") media directories, reported in plain language without
/// file-system paths. Never auto-cleaned; deletion runs through the unified
/// uninstall saga only after the user confirms.
class _OrphanWarningCard extends StatelessWidget {
  const _OrphanWarningCard({required this.orphans, this.onDelete});

  final List<StorageArtifactReport> orphans;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bytes = orphans.fold<int>(0, (sum, a) => sum + a.physicalBytes);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TurnaTheme.warningSurface(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 20, color: TurnaTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现 ${orphans.length} 个残留文件夹（共 ${_formatBytes(bytes)}）',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '这些文件已无对应课程，是之前删除牌组时中断留下的。'
                  '如确认不再需要，可以删除；删除不影响现有课程和学习进度。',
                  style: TextStyle(
                    fontSize: 12,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TurnaTheme.warning,
                        side: BorderSide(
                          color: TurnaTheme.warning.withValues(alpha: 0.5),
                        ),
                      ),
                      label: const Text('删除残留文件'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.snapshot});

  final RuntimeMemorySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final rss = snapshot?.currentRssBytes;
    final sampledAt = snapshot?.sampledAt;
    return Container(
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
                  '当前运行内存',
                  style: TextStyle(
                    fontSize: 13,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              ),
              Text(
                rss == null ? '当前平台不可用' : _formatBytes(rss),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.brandTeal,
                ),
              ),
              if (rss != null && sampledAt != null)
                Text(
                  ' · 采样于 ${_formatShortTime(sampledAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: TurnaTheme.textHintColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '这是 App 运行时占用的内存，和磁盘上的文件大小是两回事。',
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Static donut showing each category's share of total disk usage. No
/// animation — repaints only when the segment values change.
class _ShareRingPainter extends CustomPainter {
  const _ShareRingPainter({
    required this.segments,
    required this.trackColor,
  });

  final List<({double value, Color color})> segments;
  final Color trackColor;

  static const double _strokeWidth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.butt;

    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) {
      paint.color = trackColor;
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      return;
    }
    var start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = segment.value / total * math.pi * 2;
      paint.color = segment.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_ShareRingPainter oldDelegate) {
    if (oldDelegate.trackColor != trackColor ||
        oldDelegate.segments.length != segments.length) {
      return true;
    }
    for (var i = 0; i < segments.length; i++) {
      if (oldDelegate.segments[i].value != segments[i].value ||
          oldDelegate.segments[i].color != segments[i].color) {
        return true;
      }
    }
    return false;
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TurnaTheme.error.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            border: Border.all(color: TurnaTheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: const TextStyle(color: TurnaTheme.error, fontSize: 13),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
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
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} ${_formatShortTime(time)}';
}

String _formatShortTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
