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
import 'package:turna/application/maintenance/official_anki_ghost_purge_service.dart';
import 'package:turna/application/maintenance/official_storage_optimize_service.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/storage_category_items_page.dart';
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
      label: 'AI response cache',
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
    StorageInventoryService scanner, {
    Future<OfficialStorageOptimizeResult> Function({required bool force})?
        optimize,
    Future<List<StorageDeletableItem>> Function()? listOfficialSources,
    Future<bool> Function(String id)? uninstall,
    Future<OfficialAnkiGhostPurgeResult> Function()? forcePurgeOfficial,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StorageDiagnosticsPage(
          scanner: scanner,
          optimizeDatabases: optimize,
          listOfficialSources: listOfficialSources,
          uninstall: uninstall,
          forcePurgeOfficial: forcePurgeOfficial,
        ),
      ),
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
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

  testWidgets('optimize button confirms then calls force compact',
      (tester) async {
    var calls = 0;
    var lastForce = false;
    await pumpPage(
      tester,
      _FakeScanner(_cannedReport),
      optimize: ({required bool force}) async {
        calls++;
        lastForce = force;
        return const OfficialStorageOptimizeResult(ok: true, completedJobs: 3);
      },
    );

    expect(find.text(AppStrings.storageOptimizeDatabase), findsOneWidget);
    await tester.tap(find.byKey(const Key('storage-optimize-db')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.storageOptimizeConfirmTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(
      FilledButton,
      AppStrings.storageOptimizeDatabase,
    ));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(lastForce, isTrue);
    expect(find.text(AppStrings.storageOptimizeDone(3)), findsOneWidget);
  });

  testWidgets('optimize cancel does not call compact', (tester) async {
    var calls = 0;
    await pumpPage(
      tester,
      _FakeScanner(_cannedReport),
      optimize: ({required bool force}) async {
        calls++;
        return const OfficialStorageOptimizeResult(ok: true);
      },
    );

    await tester.tap(find.byKey(const Key('storage-optimize-db')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('official collection drill-down deletes selected sources',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final uninstalled = <String>[];
    await pumpPage(
      tester,
      _FakeScanner(_cannedReport),
      listOfficialSources: () async => const [
        StorageDeletableItem(
          id: 'src-alpha-full-id',
          displayName: 'Alpha Deck',
          subtitle: '使用中',
        ),
        StorageDeletableItem(
          id: 'src-beta-full-id',
          displayName: 'Beta Deck',
          subtitle: '使用中',
        ),
      ],
      uninstall: (id) async {
        uninstalled.add(id);
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('storage-category-official')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Deck'), findsOneWidget);
    expect(find.text('Beta Deck'), findsOneWidget);

    await tester.tap(find.byKey(const Key('storage-item-src-alpha-full-id')));
    await tester.tap(find.byKey(const Key('storage-item-src-beta-full-id')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('storage-delete-selected')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ankiUninstallConfirmTitle), findsOneWidget);
    await tester.tap(find.text(AppStrings.ankiUninstallDeck));
    await tester.pumpAndSettle();
    expect(uninstalled, ['src-alpha-full-id', 'src-beta-full-id']);
    expect(find.text(AppStrings.ankiDeckRemoved), findsOneWidget);
  });

  testWidgets('official collection cancel does not uninstall', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;
    await pumpPage(
      tester,
      _FakeScanner(_cannedReport),
      listOfficialSources: () async => const [
        StorageDeletableItem(
          id: 'src-only',
          displayName: 'Only Deck',
          subtitle: '使用中',
        ),
      ],
      uninstall: (id) async {
        calls++;
        return true;
      },
    );
    await tester.tap(find.byKey(const Key('storage-category-official')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('storage-item-src-only')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('storage-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('media drill-down uninstalls owned folders', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final report = StorageInventoryReport(
      artifacts: [
        ..._cannedReport.artifacts,
        StorageArtifactReport(
          category: StorageArtifactCategory.legacyAnkiMedia,
          ownerId: 'import-owned-1',
          label: 'owned-media',
          physicalBytes: 1024,
          fileCount: 2,
          cleanupPolicy: StorageCleanupPolicy.deleteSaga,
        ),
      ],
      databaseWalBytes: _cannedReport.databaseWalBytes,
      databaseShmBytes: _cannedReport.databaseShmBytes,
      freelistBytes: _cannedReport.freelistBytes,
      aiCacheEntries: _cannedReport.aiCacheEntries,
      scannedAt: _cannedReport.scannedAt,
    );
    final uninstalled = <String>[];
    await pumpPage(
      tester,
      _FakeScanner(report),
      uninstall: (id) async {
        uninstalled.add(id);
        return true;
      },
    );
    await tester.tap(find.byKey(const Key('storage-category-media')));
    await tester.pumpAndSettle();
    expect(find.text('import-owned-1'), findsOneWidget);
    expect(find.textContaining('media/'), findsNothing);
    await tester.tap(find.byKey(const Key('storage-item-import-owned-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('storage-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.ankiUninstallDeck));
    await tester.pumpAndSettle();
    expect(uninstalled, ['import-owned-1']);
  });

  testWidgets('empty official collection disables delete', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpPage(
      tester,
      _FakeScanner(_cannedReport),
      listOfficialSources: () async => const [],
    );
    await tester.tap(find.byKey(const Key('storage-category-official')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.storageOfficialCollectionEmpty), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('storage-delete-selected')),
    );
    expect(button.onPressed, isNull);
    expect(find.byKey(const Key('storage-force-purge')), findsNothing);
  });

  testWidgets('ghost official leftover offers force purge', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final report = StorageInventoryReport(
      artifacts: [
        ..._cannedReport.artifacts,
        StorageArtifactReport(
          category: StorageArtifactCategory.officialAnki,
          ownerId: 'profile-default-01',
          label: 'leftover-collection',
          physicalBytes: 8192,
          fileCount: 3,
          cleanupPolicy: StorageCleanupPolicy.deleteSaga,
        ),
      ],
      databaseWalBytes: _cannedReport.databaseWalBytes,
      databaseShmBytes: _cannedReport.databaseShmBytes,
      freelistBytes: _cannedReport.freelistBytes,
      aiCacheEntries: _cannedReport.aiCacheEntries,
      scannedAt: _cannedReport.scannedAt,
    );
    var purges = 0;
    await pumpPage(
      tester,
      _FakeScanner(report),
      listOfficialSources: () async => const [],
      forcePurgeOfficial: () async {
        purges++;
        return const OfficialAnkiGhostPurgeResult(ok: true, deletedEntries: 3);
      },
    );
    await tester.tap(find.byKey(const Key('storage-category-official')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.storageForcePurgeOfficialHint), findsOneWidget);
    expect(find.byKey(const Key('storage-force-purge')), findsOneWidget);

    await tester.tap(find.byKey(const Key('storage-force-purge')));
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.storageForcePurgeOfficialConfirmTitle),
      findsOneWidget,
    );
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();
    expect(purges, 0);

    await tester.tap(find.byKey(const Key('storage-force-purge')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
      FilledButton,
      AppStrings.storageForcePurgeOfficial,
    ));
    await tester.pumpAndSettle();
    expect(purges, 1);
    expect(find.text(AppStrings.storageForcePurgeOfficialDone), findsOneWidget);
  });

  testWidgets('force purge hidden when official sources exist', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final report = StorageInventoryReport(
      artifacts: [
        StorageArtifactReport(
          category: StorageArtifactCategory.officialAnki,
          ownerId: 'profile-default-01',
          label: 'collection',
          physicalBytes: 8192,
          fileCount: 1,
          cleanupPolicy: StorageCleanupPolicy.deleteSaga,
        ),
      ],
      databaseWalBytes: 0,
      databaseShmBytes: 0,
      freelistBytes: 0,
      aiCacheEntries: 0,
      scannedAt: DateTime(2026, 8, 23, 12, 0),
    );
    await pumpPage(
      tester,
      _FakeScanner(report),
      listOfficialSources: () async => const [
        StorageDeletableItem(
          id: 'src-live',
          displayName: 'Live Deck',
          subtitle: '使用中',
        ),
      ],
      forcePurgeOfficial: () async =>
          const OfficialAnkiGhostPurgeResult(ok: true),
    );
    await tester.tap(find.byKey(const Key('storage-category-official')));
    await tester.pumpAndSettle();
    expect(find.text('Live Deck'), findsOneWidget);
    expect(find.byKey(const Key('storage-force-purge')), findsNothing);
  });
}
