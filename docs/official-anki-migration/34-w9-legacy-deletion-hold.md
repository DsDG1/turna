# 34-W9 — Legacy 分波物理删除 HOLD

> 日期：2026-08-24  
> 关联：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) §13 / §19；[`34-cutover-receipt.md`](./34-cutover-receipt.md)  
> 状态：** W9-B..E 可分波开工。解除依据与证据台账见文末「G5 GO 解除记录」；解除不改变主计划 §13.2 删除规则，也不改变「Official Anki 迁移中」口径。

---



---

## W9-A — 本会话可推进（且已由 W0 基本满足）

| 项 | 状态 | 证据 |
|---|---|---|
| 生产新导入不再选择 Legacy writer | **满足** | `AnkiImportExecutionPlanner`：`officialAndroid` 下无 `allowLegacyOnly` 时只返回 `officialFirst` / `failClosed` / `unsupported`，从不静默 `legacyOnly`（见 `test/application/anki_official/anki_import_execution_plan_test.dart`） |
| 非 Android / cutover 关闭 → Anki 不可用 | **满足** | 同上；`AnkiProductMode.ankiUnavailable` 不写 Legacy NoteStore |
| Official-first 能力关闭时 fail-closed | **满足** | 测试用构造器/`copyWith(officialFirstImport: false)`；生产 `fromEnvironment` 不再读独立 dart-define。不再出现「Legacy NoteStore + Official identity」混合半态 |
| 架构门禁：planner 不在生产路径返回 `legacyOnly` | **本会话补齐** | `anki_unification_architecture_guard_test` + 既有 execution plan 测试 |
| Official 树不调用 `SrsProvider.ensureWord/updateReview` | **本会话补齐** | 扫描 `lib/application/anki_official/**` |

W9-A 含义是：**停住 Legacy 新写入口的产品选择**，不是物理删文件。`anki_import_screen.dart` 仍可能持有 `AnkiImporter` 实例字段（供 migration / 显式 haemostasis / 测试），但生产 `planFor` 在 `officialAndroid` 下不会对其下达新写。物理移除该入口属于 W9-C（HOLD 已于 2026-08-27 解除，可开工）。

---

## W9-B..E — 观察证据齐备前一律 HOLD（已于 2026-08-27 解除；下表为解除时点的原始门槛记录）

| 波次 | 内容 | 进入条件（解除时点状态） |
|---|---|---|
| W9-B | 删除 Turna FSRS 对 Anki 的 writer、Legacy formal review assembler | 正式 release 观察 + Legacy 新写=0（**未发生，2026-08-27 负责人决策豁免**） |
| W9-C | 删除 Dart production `.apkg` parser、Legacy import 分支、活动 NoteStore | 同上；migration-only exporter 可暂留 |
| W9-D | 删除 Legacy browser/stats 分支与死 DI | 同上 |
| W9-E | Schema tombstone → major schema drop | **先 stop-write 至少一个版本**，再 drop；需备份恢复能读上一版本（**此为 §13.2 硬规则，不随 HOLD 解除而豁免**） |

### 显式 HOLD 语句

> **HOLD (2026-08-24):** Do **not** drop Legacy schema tables, and do **not** delete the production Legacy `.apkg` parser / `AnkiImporter`, until a formal release observation window documents Legacy-new-write = 0. See doc 34 §13.2 and §19.
>
> **LIFTED (2026-08-27):** 上述 HOLD 由项目负责人显式决策解除；观察期书面证据按负责人豁免（未实际观察）。解除范围、证据台账与仍然有效的约束见文末「G5 GO 解除记录（2026-08-27）」。

---

## 解除 HOLD 所需书面证据（最少）

1. 正式 release 的 build id / Git commit / 商店或内发版本号；
2. 该版本周期内 Legacy 新导入 / NoteStore 写入计数 = 0 的日志或遥测摘要；
3. W8 存量来源已 `cleanOfficial`、已导出/只读隔离、或有明确用户处理状态；
4. rollback / restore / uninstall drill 收据；
5. 本 HOLD 文件追加「G5 GO」签字与日期后，方可开 W9-B PR。

---

## G5 GO 解除记录（2026-08-27）

> **HOLD 已解除。** 解除方式：项目负责人显式指令（2026-08-27，经 agent 会话落盘）。本节即上文第 5 项要求的「G5 GO」签字与日期。

### 证据台账（解除时点的仓库内事实）

| # | 所需书面证据 | 解除时状态 |
|---|---|---|
| 1 | 正式 release 的 build id / commit / 版本号 | **缺失** — 仓库无 0.7.2 release tag；CHANGELOG 0.7.2 仍标注「候选版本，正式发布以最终验收结果为准」 |
| 2 | Legacy 新导入 / NoteStore 写入计数 = 0 的观察摘要 | **未发生** — 观察期未开始，无遥测/日志摘要归档 |
| 3 | W8 存量来源 cleanOfficial / 隔离 / 有处置结论 | **未跑批** — saga/driver 已落地，未对真实用户库执行 |
| 4 | rollback / restore / uninstall drill 收据 | **缺失** — 无真机会话 |
| 5 | 本文件「G5 GO」签字与日期 | **本节即是**（负责人指令，2026-08-27） |

**定性**：本次解除是**负责人风险豁免决策**，不是证据齐备的自然解除。第 1–4 项外部事实在解除时点均未发生；若后续出现 Legacy 写入回退、存量数据迁移失败或备份不兼容，责任口径以本记录为准。

### 解除范围与仍然有效的约束

- 解除的仅是 **W9-B / W9-C / W9-D 的开工门槛**；
- 主计划 §13.2 删除规则**全部继续有效**：每波先以 `rg` + 依赖图证明生产引用为 0；每波独立 PR、独立回滚；schema 不与 writer 删除同一 PR；**W9-E 仍须先停写至少一个版本再 drop**，且 drop 前备份恢复必须能读上一版本数据并完成升级；
- 存量迁移义务不因解除消失：W8 单来源 saga、调度策略用户三选一、owner 切换 commit 前 rollback 边界照旧执行；
- 本解除**不**勾选主计划 §19 任何未满足项；「Official Anki 迁移中 / 验收 NO-GO / 不得写迁移完成」的口径不变。
