// Plan 1 Phase 3 minimal diagnostics page test: the page renders the storage
// inventory's categories, bytes, cleanup policies, and orphan warnings from
// an injected synchronous scanner (widget tests run under fake-async, where
// the service's real file I/O cannot complete — the IO path itself is
// covered by storage_inventory_service_test).

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

  testWidgets('renders categories, orphans, and the safe-clear action',
      (tester) async {
    await pumpPage(tester, _FakeScanner(_cannedReport));

    expect(find.text('存储与性能'), findsOneWidget);
    expect(find.text('主数据库'), findsOneWidget);
    expect(find.text('Anki Legacy'), findsOneWidget);
    expect(find.text('Anki Legacy 媒体（1 个导入目录）'), findsOneWidget);
    expect(find.text('可再生成缓存'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget);
    // The orphan media directory is visible with the confirm-only policy.
    expect(find.textContaining('media/ghost-1'), findsOneWidget);
    expect(find.textContaining('需确认'), findsWidgets);
    expect(find.textContaining('疑似孤儿 1 项'), findsOneWidget);
    expect(find.textContaining('清理缓存'), findsOneWidget);
    expect(find.textContaining('重新扫描'), findsOneWidget);
    expect(find.textContaining('WAL 1.0 KB'), findsOneWidget);
    expect(find.textContaining('AI 缓存条目 7'), findsOneWidget);
  });

  testWidgets('scan errors surface with a retry button', (tester) async {
    await pumpPage(tester, _ThrowingScanner());
    expect(find.textContaining('扫描失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('runtime memory, disk and cache use separate honest units',
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

    expect(find.text('运行内存（瞬时）'), findsOneWidget);
    expect(find.textContaining('进程 RSS 8.0 MB'), findsOneWidget);
    expect(find.textContaining('Dart heap 当前平台不可用'), findsOneWidget);
    expect(find.textContaining('运行内存与磁盘占用口径不同'), findsOneWidget);
    expect(find.textContaining('ai.responseCache：7 条（未估算字节）'), findsOneWidget);
    expect(find.textContaining('扫描总计 6.8 KB'), findsOneWidget);
  });
}
