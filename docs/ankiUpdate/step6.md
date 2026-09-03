# Step 6 详细说明：分批退役旧代码与旧表收敛（单一事实源闭环）

> **现行施工规划（2026-09-02）**。
> 上游文档：[README.md](./README.md)（总目标与六步计划）；前置：[step4.md](./step4.md)（已关闭，生产 `v2ImportChain=true` 翻转生效）、[step5.md](./step5.md)（存量迁移重新决策定案）、[ADR 0043](../decisions/0043-anki-v2-single-source-of-truth.md)、[ADR 0044](../decisions/0044-anki-v2-revival.md)。
> Step 6 的使命：**兑现 ADR 0043 的全部架构承诺**——将系统从「v1/v2 双轨并存」推进到「单一事实源终局」。物理删除 catalog 13 张旧表（18→5）与 course.db 11 张旧表，彻底退役 v1 投影流水线、跨库对账器、Legacy 迁移模块，移除过渡 flag，代码量从约 33k 行降至约 15k 行，并建立自动化 Guard 锁门测试。

---

## 0. 范围围栏（先说清楚不做什么）

| 不做 | 归属 / 原因 |
|---|---|
| 动 Rust 桥内核（42 个 op、AArch64 ELF .so、isolate 会话 RPC） | 地基资产，严格保持不动（README「不动」清单） |
| 动复习会话层、答题回执、卡面渲染层、字段识别器 | 业务核心资产，原样保留 |
| 动内置 Turkish 课程体系 | 不走 Anki 存储链路，严格隔离不受影响 |
| 重启已作废的「PR2 catalog 迁 drift」 | 已被 ADR 0044 条 4 取代：直接删表，禁止做无意义的中途迁移 |
| 恢复或兼容 pre-0042 checkpoint 历史残件 | checkpoint 体系已废除，随本步直接物理扫除 |

Step 6 的产出是：**Catalog 物理降至 5 张表（v14） + Course.db 物理收敛（v24） + v1 代码与过渡 Flag 彻底删除 + 核心 Guard 测试全绿锁门**。

---

## 1. 开工前置门禁（不满足不开工）

必须满足以下三项硬门禁，方可启动代码与数据库的物理删除：

1. **Step 4 已在生产关闭**：`productionAndroid.v2ImportChain = true` 已生效（见 [step4-r4-runbook.md](./step4-r4-runbook.md)），真机强杀矩阵（K4–K14）与 C4 大库冷重建定标均在实机通过。
2. **观察期无致命阻断**：生产构建新导入包在真机能正常生成课程树、可进课、可学、可卸载；修复中心零不可收敛的 v2 quarantine 异常。
3. **Step 5 存量处置定案**：
   - 若执行了 Step 5，则所有存量 v1 source 已通过三样短事务升级为 `chain='v2'` 并入队重建了视图；
   - 若产品决策跳过 Step 5（放弃老数据），则确认已知悉：**旧表一旦物理 DROP，未迁移的 v1 来源将不可逆失效**。

---

## 2. 表物理收敛与 Schema 升级方案

本次重构涉及两个独立 SQLite 数据库的 Schema 升级，必须在同一次发版中原子闭环。

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Catalog 数据库: v13 → v14                                │
│    18 张表 ─────────────── 物理 DROP 13 张 ───────────────► 5 张核心表 │
│    (保留: anki_sources, anki_source_cards,                  │
│           anki_import_attempts,                             │
│           anki_maintenance_jobs, anki_maintenance_leases)   │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ 2. CourseDatabase (course.db): v23 → v24                    │
│    13 张 anki 表 ──────── 物理 DROP 11 张 ───────────────► 2 张表    │
│    (保留: anki_course_tree_view [物化视图],                 │
│           anki_card_introduction_states [引入状态])        │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 Catalog 数据库升级：v13 → v14（18 表 → 5 表）

#### 变更目标
- 目标版本：`kOfficialAnkiCatalogSchemaVersion = 14`
- 文件路径：`lib/application/anki_official/storage/official_anki_database.dart`
- 仅保留 **5 张核心账本表**：
  1. `anki_sources`（来源元数据，包含 `chain` 列）
  2. `anki_source_cards`（所有权索引，删除原语 op 31/32 的输入）
  3. `anki_import_attempts`（已吸收 receipt 列）
  4. `anki_maintenance_jobs`（后台任务队列）
  5. `anki_maintenance_leases`（并发排他租约）

#### 物理 DROP 的 13 张旧表
```sql
DROP TABLE IF EXISTS anki_import_attempt_notes;
DROP TABLE IF EXISTS anki_projection_mappings;
DROP TABLE IF EXISTS anki_course_placement_overrides;
DROP TABLE IF EXISTS anki_projection_jobs;
DROP TABLE IF EXISTS anki_source_projection_state;
DROP TABLE IF EXISTS anki_source_reconciliation_journal;
DROP TABLE IF EXISTS anki_source_notetypes;
DROP TABLE IF EXISTS anki_source_decks;
DROP TABLE IF EXISTS anki_checkpoint_files;
DROP TABLE IF EXISTS anki_cleanup_receipts;
DROP TABLE IF EXISTS legacy_anki_migrations;
DROP TABLE IF EXISTS legacy_anki_card_map;
DROP TABLE IF EXISTS anki_scheduler_mutations;
```

#### 物理 DROP 的 13 张旧表（严格按子表到父表顺序排列）

> **技术注意**：`official_anki_database.dart` 的 `_migrate()` 在 `BEGIN...COMMIT` 事务内执行。在 SQLite 规范中，事务内的 `PRAGMA foreign_keys = OFF` 是无操作（no-op）。为确保在任何外键检查级别下均零报错，必须**严格按从表（子表）到主表（父表）的逆向依赖顺序**执行 DROP：

```sql
-- 1. 先删带有外键约束的子表（从表）
DROP TABLE IF EXISTS legacy_anki_card_map;           -- 引用 legacy_anki_migrations
DROP TABLE IF EXISTS anki_import_attempt_notes;      -- 引用 anki_import_attempts
DROP TABLE IF EXISTS anki_source_notetypes;          -- 引用 anki_sources
DROP TABLE IF EXISTS anki_source_decks;              -- 引用 anki_sources
DROP TABLE IF EXISTS anki_projection_jobs;           -- 引用 anki_sources
DROP TABLE IF EXISTS anki_course_placement_overrides;-- 引用 anki_sources
DROP TABLE IF EXISTS anki_source_projection_state;   -- 引用 anki_sources

-- 2. 再删无外部从表引用的父表与独立表
DROP TABLE IF EXISTS legacy_anki_migrations;
DROP TABLE IF EXISTS anki_projection_mappings;
DROP TABLE IF EXISTS anki_source_reconciliation_journal;
DROP TABLE IF EXISTS anki_checkpoint_files;
DROP TABLE IF EXISTS anki_cleanup_receipts;
DROP TABLE IF EXISTS anki_scheduler_mutations;
```

#### 操作代码（`official_anki_database.dart`）
```dart
// 1. 常量升级
const int kOfficialAnkiCatalogSchemaVersion = 14;

// 2. 升级方法接入 _migrate()
if (version <= 13) {
  _upgradeToV14();
}

// 3. 升级具体实现（严格依赖序）
void _upgradeToV14() {
  const tablesToDrop = [
    // 子表（从表）优先
    'legacy_anki_card_map',
    'anki_import_attempt_notes',
    'anki_source_notetypes',
    'anki_source_decks',
    'anki_projection_jobs',
    'anki_course_placement_overrides',
    'anki_source_projection_state',
    // 父表与独立账本
    'legacy_anki_migrations',
    'anki_projection_mappings',
    'anki_source_reconciliation_journal',
    'anki_checkpoint_files',
    'anki_cleanup_receipts',
    'anki_scheduler_mutations',
  ];

  for (final table in tablesToDrop) {
    _db.execute('DROP TABLE IF EXISTS $table');
  }
}

// 4. 全新安装 _createV1() 重构：仅创建 5 张核心表，不再建已废弃表
```

---

### 2.2 CourseDatabase 升级：v23 → v24（13 表 → 2 表）

#### 变更目标
- 目标版本：`CourseDatabase.kSchemaVersion = 24`
- 文件路径：`lib/data/course_database.dart`
- 仅保留 **2 张 anki 相关表**：
  1. `anki_course_tree_view`（D3 唯一物化视图，无独立状态，随时可重建）
  2. `anki_card_introduction_states`（产品引入事实）

#### 物理 DROP 的 11 张旧表
```sql
DROP TABLE IF EXISTS official_anki_projection_index;
DROP TABLE IF EXISTS official_anki_projection_manifest;
DROP TABLE IF EXISTS anki_course_card_placements;
DROP TABLE IF EXISTS anki_card_presentations;
DROP TABLE IF EXISTS anki_practice_projections;
DROP TABLE IF EXISTS anki_decks;
DROP TABLE IF EXISTS anki_import_issues;
DROP TABLE IF EXISTS anki_course_sources;
DROP TABLE IF EXISTS anki_owner_transitions;
DROP TABLE IF EXISTS course_scope_repair_journal;
DROP TABLE IF EXISTS anki_import_jobs;
DROP TABLE IF EXISTS legacy_pending_migrations;
DROP TABLE IF EXISTS course_meta_v21_codec;
```

#### 操作代码（`course_database.dart`）
```dart
// 1. 版本常量升级
static const int kSchemaVersion = 24;

// 2. onUpgrade 增量升级块
if (from < 24) {
  const ankiTablesToDrop = [
    'official_anki_projection_index',
    'official_anki_projection_manifest',
    'anki_course_card_placements',
    'anki_card_presentations',
    'anki_practice_projections',
    'anki_decks',
    'anki_import_issues',
    'anki_course_sources',
    'anki_owner_transitions',
    'course_scope_repair_journal',
    'anki_import_jobs',
    'legacy_pending_migrations',
    'course_meta_v21_codec',
  ];

  for (final table in ankiTablesToDrop) {
    await m.database.customStatement('DROP TABLE IF EXISTS $table');
  }
}

// 3. 从 onCreate 与 downgrade 清单中移除废弃表的创建与辅助方法：
//    - 删除 _ensureOfficialProjectionIndex()
//    - 删除 _ensureOfficialProjectionManifest()
//    - 删除 _ensureAnkiUnificationTables() 中旧表的 CREATE
//    - 删除 _ensureOwnerAuthorityTables() 中旧表的 CREATE

> **关键工程解耦注意**：
> 1. 上述被 DROP 的 11 张旧表全部是历史上通过 `customStatement` 创建的，**并非** Drift `@DriftDatabase(tables: [...])` 中声明的 Dart Entity 表。这意味着在 `onUpgrade` 中执行 `DROP TABLE IF EXISTS` 完全不需要触发 `dart run build_runner build`，不会造成 Drift 编译产物的剧烈震荡。
> 2. **测试夹具同步**：`test/data/schema_migration_test.dart` 中存在用于验证降级行为的虚拟未来版本夹具 `class _CourseDatabaseV24 extends db.CourseDatabase`（其 `schemaVersion => kSchemaVersion + 1`）。在本次版本号提升至 24 后，该测试类必须同步重命名并指向 `_CourseDatabaseV25`，否则会导致版本降级测试逻辑出现混淆。
```

---

## 3. 代码分批删除与退役操作手册

采用 4 阶段渐进删除，每完成一个阶段必须运行受影响目录的定向测试与分析，确保零编译错误。

```
Phase 1: 退役 v1 投影流水线 ──► Phase 2: 退役 Legacy 迁移与对账系统
               │                                      │
               ▼                                      ▼
Phase 3: 纯化 DAO 与退役过渡 Flag ──► Phase 4: 测试清扫与 Guard 锁门
```

### 阶段 1 (Phase 1)：退役 v1 投影流水线（Projector & Projection Store）

**目标**：删除依赖 `official_anki_projection_index` 与 catalog 投影状态的旧生成流水线。

1. **直接删除的文件**（`lib/application/anki_official/projection/`）：
   - `official_anki_projection_service.dart`（~40 KB，v1 投影协调服务）
   - `official_anki_projection_projector.dart`（~24 KB，v1 批处理卡片投影计算）
   - `official_anki_projection_store.dart`（~18 KB，v1 投影索引读写器）
   - `official_anki_projection_jobs.dart`（~15 KB，v1 投影任务模型与状态机）
   - `official_anki_projection_canonical.dart`（~5 KB，v1 规范化）
   - `official_anki_projection_fingerprint.dart`（~4 KB，v1 指纹算法）
   - `official_anki_projection_paging.dart`（~1 KB，若仅被旧投影使用）
2. **保留并提炼的共享文件**：
   - `official_anki_projection_payloads.dart`：保留！内含 `LessonInteraction` 编解码逻辑，被 `v2/official_anki_v2_lesson_content.dart` 深度复用。
   - `official_exercise_presets.dart`：保留，供练习模块使用。
   - `official_anki_course_entry.dart`：精简，移除 `lookupActiveSectionIdsAsync` 对旧投影表的回退查询，只查 `anki_course_tree_view`。
   - `official_anki_lesson_card_index.dart`：精简，移除非 v2 的 fallback 逻辑，直接通过视图解析。

---

### 阶段 2 (Phase 2)：退役 Legacy 迁移与对账系统（Reconciler & Legacy Sagas）

**目标**：删除曾用于旧版本（Legacy Drift Anki -> Official Anki v1）迁移的全部临时设施，删除跨库对账日志。

1. **直接删除的文件**（`lib/application/anki_official/migration/` 几乎整目录清空 + 关联废弃文件）：
   - `migration/official_anki_source_reconciler.dart`（~33 KB，对账器与修复中心写栅栏）
   - `migration/official_legacy_source_migration_saga.dart`（~36 KB，老迁移 Saga）
   - `migration/official_legacy_migration_coordinator.dart`（~25 KB，迁移协调器）
   - `migration/official_anki_production_router.dart`（~16 KB，Legacy↔Official 路由）
   - `migration/official_anki_migration_dao.dart`（~14 KB，老迁移 DAO）
   - `migration/official_anki_backup_manifest.dart`（~9 KB）
   - `migration/official_anki_dry_run_matcher.dart` / `official_anki_dry_run_saga.dart`（~10 KB）
   - `migration/official_anki_joined_evidence_reader.dart`（~7 KB）
   - `migration/official_anki_census.dart` / `official_anki_startup_census.dart`（~8 KB）
   - `migration/official_anki_write_owner.dart`（~3 KB）
   - `migration/official_legacy_migration_driver.dart`（~3 KB）
   - `migration/official_first_reanchor.dart`（~2 KB）
   - `lifecycle/official_anki_source_metadata_dao.dart`（~3.6 KB，仅服务于已删的 notetypes/decks/mappings 表）
   - `lifecycle/official_anki_checkpoint_dao.dart`（~3 KB，仅服务于已删的 checkpoints 表）
   - `lifecycle/official_anki_uninstall_saga.dart`（~9 KB，v1 卸载流程，已完全由 v2_retire_service 替代）
   - `import/official_anki_recovery_service.dart`（~1.2 KB，v1 导入编排恢复）
   - `import/official_anki_commit_receipt.dart`（~2.4 KB，已由 v2/official_anki_v2_card_index 替代）
2. **清理核心调用方与关键依赖**：
   - **`lib/application/anki_official/lifecycle/official_anki_storage_audit.dart`**：
     - 必须移除对已删表的 SQL 统计：`SELECT COUNT(*) FROM anki_projection_mappings` 与 `SELECT COUNT(*) FROM anki_checkpoint_files WHERE state = 'ready'`；
     - 否则用户进入修复中心导出诊断时会抛出 `no such table: anki_projection_mappings` 异常。
   - **`lib/application/anki_official/anki_deck_manager.dart`（卸载路由简化）**：
     - 简化 `_resolveDeletionOwner`：彻底删除其对 `_locateAuthorityDao()` 与 `OfficialAnkiMigrationDao` 的前置多级嗅探；
     - 在 v2 单轨下，直接通过 `OfficialAnkiSourceDao.findById(importId) != null` 确权并走 `_uninstallV2Source`。
   - **`lib/application/anki_official/lifecycle/official_anki_maintenance.dart`**：
     - 移除 `reconcile`、`census`、`checkpoint` 相关的 job 执行分支，仅保留 `mediaGc`、`compact`、`v2_source_delete`、`v2_view_rebuild`。
   - **`lib/views/settings/official_anki_repair_center_page.dart`**：
     - 移除针对 Legacy 对账冲突、双写栅栏的修复动作，诊断仅保留存储体积快照、视图重建与日志导出。

---

### 阶段 3 (Phase 3)：纯化 DAO、读写路由与退役过渡 Flag（单轨化）

**目标**：消除分支判断，v2 成为系统内唯一标准路径，移除 `chain == 'v2'` 兼容分支。

1. **DAO 层精简**：
   - `lib/application/anki_official/storage/official_anki_source_dao.dart`：
     - 删除对 `anki_projection_mappings`、`anki_course_placement_overrides`、`anki_source_decks` 等表的全部操作方法。
     - 来源查询移除 `chain` 过滤或默认所有来源均为原生标准来源。
   - `lib/application/anki_official/storage/official_anki_import_attempt_dao.dart`：
     - 仅操作 `anki_import_attempts` 单表，清理对 `anki_import_attempt_notes` 的联表查询。
2. **导入控制面纯化**：
   - `lib/views/anki/anki_import_controller.dart`：
     - 彻底删除 `_commitOfficialV1` 分支及其引用的 `UnifiedAnkiImportOrchestrator.publishFromProjection`。
     - 统一仅调用 `_commitOfficialV2`（直接调用 `OfficialAnkiV2ImportService.commit`）。
   - `lib/application/anki_official/import/official_anki_official_first_service.dart`：
     - 移除旧 metadata 关联写入，全面直通 v2 决策区与视图层。
3. **退役过渡 Flag**：
   - `lib/application/anki_official/official_anki_feature_flags.dart`：
     - 废除 `v2ImportChain` 布尔位；
     - `allowsV2ImportChain` getter 恒返回 `true`（或内联移除其所有调用方）；
     - 移除已废弃的编译期 Define 说明。
4. **读路径纯化**：
   - `CourseProvider` / `CourseCatalog`：移除从 drift 旧表（`sections`/`units`/`lessons`）拼装 Anki 课程的遗留 fallback，统一从 `OfficialAnkiV2CourseRead` / `OfficialAnkiV2ViewStore` 获取。

---

### 阶段 4 (Phase 4)：测试用例清扫与 Guard 锁门测试建立

**目标**：删除死测试，编写自动化 Guard 测试，防止旧架构死灰复燃。

1. **删除失效的旧测试用例**：
   - 删除 `test/application/anki_official/` 下对应的 `projection/`、`migration/`、旧 saga 测试文件。
2. **编写架构锁门测试（Guard Test）**：
   - 新建 `test/application/anki_official/official_anki_v2_monolith_lockout_guard_test.dart`（见第 4 节具体代码）。
3. **更新 Schema 锁门测试**：
   - 更新 `test/application/anki_official/storage/official_anki_lifecycle_storage_test.dart`：断言 catalog 表严格等于 5，且不含任何已删表。

---

## 4. 核心可操作代码与实施脚本

### 4.1 核心 Guard 锁门测试代码

新建文件：`test/application/anki_official/official_anki_v2_monolith_lockout_guard_test.dart`

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

void main() {
  group('Official Anki v2 Monolith Lockout Guard', () {
    test('Catalog 严格仅保留 5 张核心表', () {
      final db = OfficialAnkiDatabase.memory();
      try {
        final tables = db.handle
            .select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            .map((row) => row['name'] as String)
            .toSet();

        const expectedTables = {
          'anki_sources',
          'anki_source_cards',
          'anki_import_attempts',
          'anki_maintenance_jobs',
          'anki_maintenance_leases',
        };

        expect(tables, equals(expectedTables),
            reason: 'Catalog 表集合必须严格收敛至 5 张表，不得存在废弃表或悬挂表');
      } finally {
        db.close();
      }
    });

    test('禁止在源码树中重新引入已退役的 v1 类与符号', () {
      const forbiddenSymbols = [
        'OfficialAnkiProjectionProjector',
        'OfficialAnkiProjectionService',
        'OfficialAnkiProjectionStore',
        'OfficialAnkiSourceReconciler',
        'OfficialLegacySourceMigrationSaga',
        'OfficialAnkiProductionRouter',
        'anki_projection_mappings',
        'anki_course_placement_overrides',
        'official_anki_projection_index',
        'official_anki_projection_manifest',
      ];

      final roots = ['lib/application/anki_official', 'lib/views/anki'];
      final violations = <String>[];

      for (final root in roots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;

        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          final content = file.readAsStringSync();
          for (final symbol in forbiddenSymbols) {
            if (content.contains(symbol)) {
              violations.add('${file.path} 包含了已退役符号: $symbol');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: '生产代码不得重新引入已退役的 v1 投影/对账/旧表符号:\n${violations.join('\n')}');
    });

    test('v2 导入与读取不再依赖双轨 Flag 门禁', () {
      final file = File('lib/application/anki_official/official_anki_feature_flags.dart');
      expect(file.existsSync(), isTrue);
      final text = file.readAsStringSync();
      expect(text.contains('v2ImportChain'), isFalse,
          reason: 'v2ImportChain flag 必须退役，v2 成为常驻唯一路径');
    });
  });
}
```

### 4.2 批量文件清理脚本（PowerShell）

在实施 Phase 1 与 Phase 2 删除时，可在项目根目录下通过 PowerShell 执行批量清理：

```powershell
# 1. 删除 Phase 1 废弃投影文件
$phase1Files = @(
    "lib/application/anki_official/projection/official_anki_projection_service.dart",
    "lib/application/anki_official/projection/official_anki_projection_projector.dart",
    "lib/application/anki_official/projection/official_anki_projection_store.dart",
    "lib/application/anki_official/projection/official_anki_projection_jobs.dart",
    "lib/application/anki_official/projection/official_anki_projection_canonical.dart",
    "lib/application/anki_official/projection/official_anki_projection_fingerprint.dart"
)
foreach ($f in $phase1Files) {
    if (Test-Path $f) { Remove-Item $f -Force; Write-Host "Deleted: $f" }
}

# 2. 删除 Phase 2 废弃迁移、对账与旧 Saga 文件
$phase2Files = @(
    "lib/application/anki_official/migration/official_anki_source_reconciler.dart",
    "lib/application/anki_official/migration/official_legacy_source_migration_saga.dart",
    "lib/application/anki_official/migration/official_legacy_migration_coordinator.dart",
    "lib/application/anki_official/migration/official_anki_production_router.dart",
    "lib/application/anki_official/migration/official_anki_migration_dao.dart",
    "lib/application/anki_official/migration/official_anki_backup_manifest.dart",
    "lib/application/anki_official/migration/official_anki_dry_run_matcher.dart",
    "lib/application/anki_official/migration/official_anki_dry_run_saga.dart",
    "lib/application/anki_official/migration/official_anki_joined_evidence_reader.dart",
    "lib/application/anki_official/migration/official_anki_census.dart",
    "lib/application/anki_official/migration/official_anki_startup_census.dart",
    "lib/application/anki_official/migration/official_anki_write_owner.dart",
    "lib/application/anki_official/migration/official_legacy_migration_driver.dart",
    "lib/application/anki_official/migration/official_first_reanchor.dart",
    "lib/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart",
    "lib/application/anki_official/lifecycle/official_anki_checkpoint_dao.dart",
    "lib/application/anki_official/lifecycle/official_anki_uninstall_saga.dart",
    "lib/application/anki_official/import/official_anki_recovery_service.dart",
    "lib/application/anki_official/import/official_anki_commit_receipt.dart"
)
foreach ($f in $phase2Files) {
    if (Test-Path $f) { Remove-Item $f -Force; Write-Host "Deleted: $f" }
}
```

---

## 5. 执行顺序与操作步骤

```
步骤 1: 执行前置门禁核对（Step 4 生产运行稳定、Step 5 处置定案）
   │
步骤 2: 实施 Catalog v14 升级（删除 13 张旧表定义与 DDL）
   │
步骤 3: 实施 CourseDatabase v24 升级（删除 11 张旧表 DDL）
   │
步骤 4: 执行 Phase 1 投影流水线代码删除
   │
步骤 5: 执行 Phase 2 迁移与对账代码删除
   │
步骤 6: 执行 Phase 3 纯化 DAO、读写控制器，移除过渡 Flag
   │
步骤 7: 执行 Phase 4 清理废弃测试，落地 Guard 锁门测试
   │
步骤 8: 运行 flutter analyze 与全面定向测试套件
   │
步骤 9: 回填本收据表，正式关闭 Step 6，宣告 Anki 底座 v2 重建大功告成！
```

---

## 6. 验收清单（Checklist）

- [x] **门禁确认**：前置三项硬门禁均在开工前确认满足
- [x] **Catalog 收敛**：`official_catalog.sqlite` 物理收敛至 5 张表（`kOfficialAnkiCatalogSchemaVersion = 14`）
- [x] **Course.db 收敛**：`course.db` 中的旧 anki 投影与元数据表全部物理 DROP（`kSchemaVersion = 24`）
- [x] **代码量指标**：`lib/application/anki_official/` 代码量显著下降（删除 15k+ 行旧代码，目标整体控制在约 15k 行）
- [x] **Flag 完全退役**：`v2ImportChain` 完全退役，无任何 `if (v2)` 双轨分支，v2 成为全系统唯一底座
- [x] **Guard 锁门测试通过**：
  - [x] Catalog 5 表严格匹配断言通过
  - [x] 源码静态扫描禁止引入旧符号通过
  - [x] 视图重建与删除序列零回归
- [x] **静态分析零错误**：`flutter analyze` 报告 `No issues found!`（改动文件零 issue）
- [ ] **真机冒烟验证**：
  - [ ] 升级新包冷启动正常（两库升级顺利通过）
  - [ ] 导入新牌组正常生成课程树，可进入学习与复习
  - [ ] 卸载牌组可彻底清除卡片与视图行
  - [ ] 修复中心状态健康，无残留异常

---

## 7. 工作量估计

| 阶段 / 任务 | 预估工时 | 重点难点 |
|---|---|---|
| 前置确认与 Schema 升级（Catalog v14 + Course.db v24） | 1~2 天 | 升级 DDL 的事务安全与外键保护 |
| Phase 1 投影器与投影存储删除 | 1~2 天 | 解耦共享的 interaction payload 生成逻辑 |
| Phase 2 迁移与对账模块整体剥离 | 2~3 天 | 修复中心与后台维护 runner 引用解耦 |
| Phase 3 DAO 纯化、读写单轨化、Flag 移除 | 2~3 天 | 确保课程树读面彻底纯化且无逻辑断层 |
| Phase 4 废弃测试清扫 + Guard 测试锁门 | 1~2 天 | 保证覆盖面与防复发门禁的严密性 |
| 真机冒烟与收尾回填 | 1 天 | 实际设备冷启与导入/学习闭环 |
| **合计** | **8~13 个工作日**（约 2 周） | 严守分阶段递进，绝不一次性粗暴全删 |

---

## 8. 收据（施工后回填）

| 日期 | 事项 | 结果 | 证据（Commit / 测试输出 / 运行记录） |
|---|---|---|---|
| 2026-09-02 | Step 6 施工文档定稿 | 完成 | 本文件落稿；吸收原 PR2 目标，对齐 ADR 0043 D4/D5 与 ADR 0044 条 4 |
| 2026-09-03 | Catalog v13→v14 + Course.db v23→v24 Schema 升级落地 | 完成 | `official_anki_database.dart`（`_upgradeToV14` keep 集合反查 DROP、`_createV14` 仅建 5 表）；`course_database.dart`（v24 DROP 清单 + `_ensure*` 旧 DDL 移除） |
| 2026-09-03 | Phase 1–4 旧代码删除（投影流水线 / Legacy 迁移与对账 / DAO 纯化 / Flag 退役 / 死测试清扫） | 完成 | 分支 `p1-dead-code-cleanup`：117 文件改动，净删约 1.94 万行（-20119/+702，未提交时的 `git diff --stat`）；`v2ImportChain` 布尔位移除，`allowsV2ImportChain` 恒 true |
| 2026-09-03 | P0 修复：turna 迁移包导入器写入已 DROP 的 `legacy_pending_migrations` | 完成 | 导入器改为忽略 legacy Anki 行（结果字段 `legacyIgnoredImports`，UI 提示同步），包格式与导出侧不动；`turna_migration_import_test.dart` 用例同步改写 |
| 2026-09-03 | P1 死代码清扫：mutation receipt（写已删 `anki_scheduler_mutations`）、`checkpointRelease` 全链、`OfficialProjectionSummaryReader`、`publishFromProjection`（整文件零引用删除） | 完成 | `official_anki_mutation_receipt.dart`、`unified_anki_import_orchestrator.dart` 删除；`official_anki_review_session.dart`、`official_anki_lifecycle_models.dart`、`official_anki_maintenance.dart`、`official_anki_repair_executor.dart`、`official_anki_storage_audit.dart`、`app_strings.dart` 同步清理 |
| 2026-09-03 | 测试修复与 Guard 强化：三个 views/anki 测试编译错误清零；Guard 禁入符号补 `anki_scheduler_mutations`/`legacy_pending_migrations`/`OfficialAnkiMutationReceiptStore` | 完成 | Guard + schema 迁移 + lifecycle 存储 26 项测试全绿；`flutter analyze` `No issues found!` |
| 2026-09-03 | 测试面收尾：p5f UI happy-path 测试退役（断言已删的 `anki_course_card_placements` 表与不可达的 session 导入器）；两个 formal review 测试补种 catalog 账本（reconciler 改从账本读卡）；架构 Guard 对已删 orchestrator 反转为「保持删除」断言 | 完成 | `test/views/anki`、`test/application/anki_official`、`test/application/anki` 全绿（22/293/76 项） |
| 2026-09-03 | P0 修复（续）：owner-authority 子系统整体退役——`AnkiOwnerAuthorityDao`、`LegacyWriteFence`、scope 迁移器对已删表（`anki_course_sources`/`course_scope_repair_journal`/`course_meta_v21_codec`）的全部读写；`anki_unification_dao`/`anki_note_dao` 对已删表（`anki_course_card_placements`/`anki_card_presentations`/`anki_practice_projections`/`anki_decks`/`anki_import_issues`）的语句清理；courseProvider 官方 scope 测试（9 项）种子迁到 catalog 账本 + v2 视图 | 完成 | `flutter analyze` 归零；scope 测试 9/9 全绿；review_progress / review_history / golden / lesson_flow 等剩余失败经 stash 基线比对确认为分支既有问题，与本步无关 |
| | | | |
