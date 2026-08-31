# 43 — 存储优化 + 修复中心 UI（施工中）

> 状态：**施工中（未提交）**。对照计划 `.cursor/plans/storage_repair_ui_63309ae5.plan.md` 与 [doc 41 §12.4 / §13.3](./41-official-anki-lifecycle-and-storage-remediation-plan.md)。
> 范围修订（2026-08-31）：真机 `collection.anki2` 字节回收收据整体 **deferred**，不写假数字。

---

## 1. 已落地（工作树，未 commit）

### A. 存储页一键「优化数据库」（todo `optimize-storage`）

**新文件**

- [`lib/application/maintenance/official_storage_optimize_service.dart`](../../lib/application/maintenance/official_storage_optimize_service.dart)
  - `OfficialStorageOptimizeService.runForceCompact({catalog, paths, course, engine})`
  - 缺 catalog/paths → `OfficialStorageOptimizeResult(ok:false, errorCode:'capability_missing')`（fail-closed）。
  - 有则 `enqueue` `compact_collection` / `compact_catalog` / `compact_course`（同 kind 已幂等合并，见 `OfficialAnkiMaintenanceJobDao.enqueue`），再 `OfficialAnkiMaintenanceRunner(..., course: getIt<CourseDatabase>, engine: composition, forceCompact: true).runPending`。
  - 返回 `completedJobs`；失败不假装释放字节。

- [`test/application/maintenance/official_storage_optimize_service_test.dart`](../../test/application/maintenance/official_storage_optimize_service_test.dart)
  - 单测：无 catalog/paths 时 fail-closed（`capability_missing`，`completedJobs == 0`）。

**改动**

- [`lib/views/settings/storage_diagnostics_page.dart`](../../lib/views/settings/storage_diagnostics_page.dart)
  - 加 `optimizeDatabases` 测试缝（`Future<OfficialStorageOptimizeResult> Function({required bool force})?`）。
  - 加 `_optimizing` 状态 + `_optimizeDatabases()`：确认对话框（`storageOptimizeConfirmTitle/Body`，文案会短暂占用磁盘、不删课程/卡片）→ 调 `runForceCompact` → SnackBar 汇总（`storageOptimizeDone(n)` / `storageOptimizeUnavailable` / `storageOptimizeFailed`）→ `_rescan()`。
  - UI：清缓存按钮下加 `OutlinedButton.icon`（key `storage-optimize-db`），busy 时禁用 + spinner。
  - 加「打开修复中心」`TextButton`（key `storage-open-repair-center`）→ `OfficialAnkiRepairCenterRoute`。

- [`test/views/settings/storage_diagnostics_page_test.dart`](../../test/views/settings/storage_diagnostics_page_test.dart)
  - `pumpPage` 加 `optimize` 注入参数。
  - +2 widget 测试：确认后调 `force: true` 且 SnackBar 显示完成数；取消不调用。
  - 修 runtime memory 测试：`setSurfaceSize(400x1600)` 让 `_MemoryCard` 进视口（既有测试在新加按钮后视口不够，非本轮回归）。

- [`lib/application/anki_official/lifecycle/official_anki_maintenance.dart`](../../lib/application/anki_official/lifecycle/official_anki_maintenance.dart)
  - `OfficialAnkiMaintenanceJobDao` 加 `recentFailed({profileId, limit=20})`，按 `heartbeat_at_millis DESC`，供修复中心「最近失败的维护」用。

- [`lib/l10n/app_strings.dart`](../../lib/l10n/app_strings.dart)
  - +30 串：`storageOptimize*`（Database/ConfirmTitle/ConfirmBody/Busy/Done(n)/Unavailable/Failed）、`storageRepairCenterLink`、`ankiRepair*`（CenterTitle/EmptyCatalog/Empty/PendingCleanup/Quarantined/MaintenanceJobs/FailedJobs/Orphans/RetryCleanup/ExportDiagnostics/ExportCopied/DiscardConfirmTitle/Body/RetryCleanupConfirmTitle/Body/ActionUnavailable）。

### B. 独立修复中心 UI（todo `repair-center`）

**新文件**

- [`lib/views/anki_official/official_anki_repair_center_page.dart`](../../lib/views/anki_official/official_anki_repair_center_page.dart)
  - `@RoutePage() OfficialAnkiRepairCenterPage`（StatefulWidget，`SettingsScaffold`）。
  - 测试缝：`catalog` / `paths` / `scanner` / `optimizeDatabases` / `onContinueImport` / `onDiscardImport` / `onRetryCleanup` / `onExportDiagnostics`。
  - 只读分层（§13.3 最小集）：
    - 待完成导入：`OfficialAnkiPendingImportStore.list(catalog)`
    - 待清理：`anki_sources.state == 'pending_cleanup'`（`OfficialAnkiSourceDao.listSources(profileId)` 过滤）
    - 隔离：`state == 'quarantined'`
    - maintenance jobs：`OfficialAnkiMaintenanceJobDao.pending(profileId)` + `recentFailed(profileId)`
    - 无登记残留：`StorageInventoryService.scan().orphans`（`initState` 缓存 Future，避免 build 重入）
  - 白名单动作（确认后调现有实现，不新写破坏性 CAS）：
    - 继续导入 → `onContinueImport` 或 `context.router.push(AnkiImportRoute)`
    - 放弃并清理 → `onDiscardImport` 或 `OfficialAnkiImportSaga.cancelSource`（确认对话框）
    - 重试清理 → `onRetryCleanup` 或 `OfficialAnkiUninstallSaga.run`（确认对话框）
    - 优化数据库 → 同 A 的 `runForceCompact` 入口（确认对话框）
    - 导出诊断 → `OfficialAnkiStorageAudit.encode(snapshot(...))` → `Clipboard.setData` + `Share.share`（无密钥）；注入 `onExportDiagnostics` 时只回调不分享。
  - 缺 catalog → 空态说明（`ankiRepairCenterEmptyCatalog`），不崩溃。

- [`test/views/anki_official/official_anki_repair_center_page_test.dart`](../../test/views/anki_official/official_anki_repair_center_page_test.dart)
  - 内存 catalog + 临时 paths；插 1 staging source+attempt、1 `pending_cleanup` source、1 maintenance job。
  - +2 widget 测试：缺 catalog 空态；白名单动作确认后回调（continue/discard/retryCleanup/optimize `force:true`/export payload 含 `maintenancePending`）。

**改动**

- [`lib/routing/routing.dart`](../../lib/routing/routing.dart) + [`lib/routing/routing.gr.dart`](../../lib/routing/routing.gr.dart)
  - 注册 `AutoRoute(page: OfficialAnkiRepairCenterRoute.page)`（无 guard，与 mapping 页一样是产品面）。
  - `build_runner --delete-conflicting-outputs` 已重生成 `routing.gr.dart`。

- [`lib/routing/diagnostics_release_guard.dart`](../../lib/routing/diagnostics_release_guard.dart) + [`test/routing/official_diagnostics_release_guard_test.dart`](../../test/routing/official_diagnostics_release_guard_test.dart)
  - 注释说明修复中心是产品面（doc 41 S8），不进 `guardedRouteNames`。
  - 测试加 `isNot(contains('OfficialAnkiRepairCenterRoute'))` 断言。

- [`lib/views/courses/course_management_page.dart`](../../lib/views/courses/course_management_page.dart)
  - AppBar 加「打开修复中心」`IconButton`（key `course-open-repair-center`，`Icons.healing_outlined`）。
  - 底部 `OfficialPendingImportBanner` 旁加 `TextButton`（key `course-open-repair-center-footer`）。

## 2. 未做（明确推迟 / 不做）

- **真机 `collection.anki2` before/after 字节回收收据**：整体 deferred，不填 §18.3 假数字；收据写 **deferred / unverifiable**。
- Android 强杀矩阵、contract bump、M0–M9 一次性 migration 全跑。
- 自动删除 `legacy_unknown` backup、把整个 Official profile 目录当一键删除。
- 用 widget 测试冒充真机物理字节 GO。

## 3. 待办

- [ ] 跑定向测试：`storage_diagnostics_page_test` / `official_storage_optimize_service_test` / `official_anki_repair_center_page_test` / `official_diagnostics_release_guard_test`。
- [ ] `flutter analyze` 改动文件 0 issue。
- [ ] A、B 分两个独立 commit（计划要求）。
- [ ] **todo `receipts`**：回填 doc 41 §18 S8「修复中心 UI 已独立成页」、S7「存储页优化忽略阈值」；`test/BASELINE.md` 加生成行；真机字节行保持 unverifiable。

## 4. 风险 / 注意

- `routing.gr.dart` 大段重生成（773 行 diff），review 时只看 `OfficialAnkiRepairCenterRoute` 段与 import 顺序即可。
- 修复中心 `Share.share` 在测试环境用注入 `onExportDiagnostics` 绕过，避免 widget 测试拉起平台分享。
- `storage_diagnostics_page_test` 的 runtime memory 测试改了视口大小，是既有测试在新按钮加入后视口不够的修复，非本轮回归。
