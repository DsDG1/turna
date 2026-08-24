# 34-W9 — Legacy 分波物理删除 HOLD

> 日期：2026-08-24  
> 关联：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) §13 / §19；[`34-cutover-receipt.md`](./34-cutover-receipt.md)  
> 状态：**HOLD — 不得宣称 W9-B..E 物理删除完成**

---

## 为什么本会话不能诚实勾选 §19 物理删除

Doc 34 进入 W9 的硬条件包括：

- 存量 Legacy 迁移路径可用（W8）；
- **至少一个正式 release 观察周期**内 Legacy 新写入计数恒为 0（G4→G5）；
- OHOS target 已删除、rollback/restore/uninstall drill 通过。

「一个正式版本观察」是**日历/发布证据**，无法在单次施工会话内完成。因此在观察到书面 release 证据之前：

- **禁止** drop Legacy schema；
- **禁止** 删除生产 `.apkg` parser / `AnkiImporter` 本体（W9-C）；
- **禁止** 勾选 doc 34 §19「Legacy importer/scheduler/schema 按 W9 分波删除」。

本文件即为仓库内的显式 HOLD 真源。

---

## W9-A — 本会话可推进（且已由 W0 基本满足）

| 项 | 状态 | 证据 |
|---|---|---|
| 生产新导入不再选择 Legacy writer | **满足** | `AnkiImportExecutionPlanner`：`officialAndroid` 下无 `allowLegacyOnly` 时只返回 `officialFirst` / `failClosed` / `unsupported`，从不静默 `legacyOnly`（见 `test/application/anki_official/anki_import_execution_plan_test.dart`） |
| 非 Android / cutover 关闭 → Anki 不可用 | **满足** | 同上；`AnkiProductMode.ankiUnavailable` 不写 Legacy NoteStore |
| Official-first 能力关闭时 fail-closed | **满足** | 测试用构造器/`copyWith(officialFirstImport: false)`；生产 `fromEnvironment` 不再读独立 dart-define。不再出现「Legacy NoteStore + Official identity」混合半态 |
| 架构门禁：planner 不在生产路径返回 `legacyOnly` | **本会话补齐** | `anki_unification_architecture_guard_test` + 既有 execution plan 测试 |
| Official 树不调用 `SrsProvider.ensureWord/updateReview` | **本会话补齐** | 扫描 `lib/application/anki_official/**` |

W9-A 含义是：**停住 Legacy 新写入口的产品选择**，不是物理删文件。`anki_import_screen.dart` 仍可能持有 `AnkiImporter` 实例字段（供 migration / 显式 haemostasis / 测试），但生产 `planFor` 在 `officialAndroid` 下不会对其下达新写。物理移除该入口属于 W9-C，仍 HOLD。

---

## W9-B..E — 观察证据齐备前一律 HOLD

| 波次 | 内容 | 进入条件（尚未满足） |
|---|---|---|
| W9-B | 删除 Turna FSRS 对 Anki 的 writer、Legacy formal review assembler | 正式 release 观察 + Legacy 新写=0 |
| W9-C | 删除 Dart production `.apkg` parser、Legacy import 分支、活动 NoteStore | 同上；migration-only exporter 可暂留 |
| W9-D | 删除 Legacy browser/stats 分支与死 DI | 同上 |
| W9-E | Schema tombstone → major schema drop | **先 stop-write 至少一个版本**，再 drop；需备份恢复能读上一版本 |

### 显式 HOLD 语句

> **HOLD (2026-08-24):** Do **not** drop Legacy schema tables, and do **not** delete the production Legacy `.apkg` parser / `AnkiImporter`, until a formal release observation window documents Legacy-new-write = 0. See doc 34 §13.2 and §19.

---

## 解除 HOLD 所需书面证据（最少）

1. 正式 release 的 build id / Git commit / 商店或内发版本号；
2. 该版本周期内 Legacy 新导入 / NoteStore 写入计数 = 0 的日志或遥测摘要；
3. W8 存量来源已 `cleanOfficial`、已导出/只读隔离、或有明确用户处理状态；
4. rollback / restore / uninstall drill 收据；
5. 本 HOLD 文件追加「G5 GO」签字与日期后，方可开 W9-B PR。
