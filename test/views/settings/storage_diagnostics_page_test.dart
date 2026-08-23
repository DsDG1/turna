// User-facing storage overview page test: the page renders the storage
// inventory as a dashboard (total + share ring, four plain-language category
// cards, leftover-file warning) from an injected synchronous scanner (widget
// tests run under fake-async, where the service's real file I/O cannot
// complete — the IO path itself is covered by storage_inventory_service_test).
// Low-level diagnostics (WAL/RSS/write telemetry) must NOT appear here.

// Package imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/diagnostics/cache_diagnostics_registry.dart';
import 'package:turna/application/diagnostics/runtime_memory_snapshot.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/views/settings/storage_diagnostics_page.dart';

class _FakeScanner implements StorageInventoryService {
  _FakeScanner(this.report);

  final StorageInventoryReport report;

  @override
  Future<StorageInventoryReport> scan() async => report;
}

class _ThrowingScanner implements StorageInventoryService {
  @override
  Future<StorageInventoryReport> scan() async => throw StateError('boom');
}

class _PageCache implements CacheDiagnosticsAdapter {
  @override
  String get owner => 'ai.responseCache';
  @override
  Future<CacheFootprint> inspect() async => const CacheFootprint(
        owner: 'ai.responseCache',
        entries: 7,
        estimatedBytes: null,
      );
  @override
  Future<CacheClearResult> clearRegenerable() async =>
      const CacheClearResult(owner: 'ai.responseCache', clearedEntries: 7);
}

final _cannedReport = StorageInventoryReport(
  artifacts: [
    StorageArtifactReport(
      category: StorageArtifactCategory.mainDatabase,
      ownerId: '',
      label: 'course.db',
      physicalBytes: 4096,
      fileCount: 1,
      cleanupPolicy: StorageCleanupPolicy.optimize,
    ),
    StorageArtifactReport(
      category: StorageArtifactCategory.legacyAnki,
      ownerId: '',
      label: '2 imports (1 failed)',
      physicalBytes: 0,
      fileCount: 2,
      cleanupPolicy: StorageCleanupPolicy.deleteSaga,
    ),
    StorageArtifactReport(
      category: StorageArtifactCategory.legacyAnkiMedia,
      ownerId: 'ghost-1',
      label: 'media/ghost-1',
      physicalBytes: 2048,
      fileCount: 3,
      cleanupPolicy: StorageCleanupPolicy.confirmOnly,
      orphaned: true,
    ),
    StorageArtifactReport(
      category: StorageArtifactCategory.regenerableCache,
      ownerId: '',
      label: 'anki prerender cache',
      physicalBytes: 512,
      fileCount: 9,
      cleanupPolicy: StorageCleanupPolicy.safeClear,
    ),
    StorageArtifactReport(
      category: StorageArtifactCategory.logs,
      ownerId: '',
      label: 'diagnostics log',
      physicalBytes: 256,
      fileCount: 1,
      cleanupPolicy: StorageCleanupPolicy.safeClear,
    ),
  ],
  databaseWalBytes: 1024,
  databaseShmBytes: 32,
  freelistBytes: 2048,
  aiCacheEntries: 7,
  scannedAt: DateTime(2026, 8, 23, 12, 0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(
    WidgetTester tester,
    StorageInventoryService scanner,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: StorageDiagnosticsPage(scanner: scanner)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the dashboard, plain categories and the clear action',
      (tester) async {
    await pumpPage(tester, _FakeScanner(_cannedReport));

    expect(find.text('存储与性能'), findsOneWidget);
    expect(find.text('总占用'), findsOneWidget);
    // 4096 + 2048 + 512 + 256 = 6912 bytes ≈ 6.8 KB.
    expect(find.text('6.8 KB'), findsOneWidget);
    expect(find.text('学习数据'), findsOneWidget);
    expect(find.text('媒体文件'), findsOneWidget);
    expect(find.text('Anki 收藏'), findsOneWidget);
    expect(find.text('缓存与日志'), findsOneWidget);
    // The orphan media directory surfaces as a plain leftover-file warning.
    expect(find.textContaining('发现 1 个残留文件夹'), findsOneWidget);
    // 512 + 256 = 768 bytes safely reclaimable.
    expect(find.textContaining('清理缓存，可释放 768 B'), findsOneWidget);
    // Rescan moved to the app bar.
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });

  testWidgets('low-level jargon never appears on the page', (tester) async {
    await pumpPage(tester, _FakeScanner(_cannedReport));

    expect(find.textContaining('WAL'), findsNothing);
    expect(find.textContaining('SHM'), findsNothing);
    expect(find.textContaining('RSS'), findsNothing);
    expect(find.textContaining('Dart heap'), findsNothing);
    expect(find.textContaining('写放大'), findsNothing);
    expect(find.textContaining('已登记缓存'), findsNothing);
    expect(find.textContaining('AI 缓存条目'), findsNothing);
    expect(find.textContaining('孤儿'), findsNothing);
    // Raw file-system paths are not shown to users.
    expect(find.textContaining('media/ghost-1'), findsNothing);
  });

  testWidgets('scan errors surface with a retry button', (tester) async {
    await pumpPage(tester, _ThrowingScanner());
    expect(find.textContaining('扫描失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('runtime memory uses plain wording, separate from disk usage',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StorageDiagnosticsPage(
        scanner: _FakeScanner(_cannedReport),
        cacheRegistry: CacheDiagnosticsRegistry([_PageCache()]),
        memorySampler: () async => RuntimeMemorySnapshot(
          currentRssBytes: 8 * 1024 * 1024,
          dartHeapBytes: null,
          sampledAt: DateTime(2026, 8, 23, 12),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('当前运行内存'), findsOneWidget);
    expect(find.textContaining('8.0 MB'), findsOneWidget);
    expect(find.textContaining('采样于 12:00'), findsOneWidget);
    expect(find.textContaining('和磁盘上的文件大小是两回事'), findsOneWidget);
  });
}
