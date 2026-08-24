# 34 — Cutover receipt（W8–W10 收口摘要）

> 日期：2026-08-25（一次性施工 host 收口后更新）
> 状态：**验收 NO-GO；Official Anki 迁移中**（host/自动化门禁全绿、生产候选已形成；真机矩阵与外部事实未验收。不得写「迁移完成」）
> 计划真源：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)
> 剩余波次：[`34-remaining-construction-plan.md`](./34-remaining-construction-plan.md)
> HOLD：[`34-w9-legacy-deletion-hold.md`](./34-w9-legacy-deletion-hold.md)
> OHOS EOL ADR：[ADR 0041](../decisions/0041-ohos-product-eol.md)（草案曾写 0038；0038 已占用）

---

## Done（本收口有仓库证据）

### 2026-08-25 一次性施工（ANKI-CUTOVER-ONE-SHIP host 门禁）

| 项 | 证据 |
|---|---|
| R0 schema 9 回归 + 基线止血 | backup/restore 测试改读 `kSchemaVersion`/`kOfficialAnkiCatalogSchemaVersion`；`git diff --check` 0；native pin 验证 + so 重建（cutover-once/） |
| R1 CourseScope / 课程目录 / 精确卸载 | `CourseScope` codec v1 + `CourseCatalog`（authority+manifest）+ builtin 双隔离 + `anki:src` 歧义修复 + 顶栏课程名 + 导入三动作分流 + 完整 sourceId 卸载 |
| R2 保真实时复习 + Review All | fidelity-first 渲染、`OfficialFormalReviewLiveQueue`（Scheduler current 驱动、Again 重插、快照 generation）、Review All 全来源聚合 + 失败上报、Redo/Bury/Suspend |
| R3 六集合 Due repository | `OfficialFormalDueRepository`（known/unknown/unavailable、stale generation、rollback、retired reader）；`OfficialAnkiHomeDue` 薄 facade、officialDue 派生 |
| R4 write fence + 权威 owner 事务 | `LegacyWriteFence` 全 mutator 围栏（intent/token/rollback phase）；`anki_owner_transitions` + `commitOwnership` 同库原子；saga freeze 真实 CAS、权威先行、driver resume/rollback |
| R5 Browser/Stats 产品入口 | Official 牌组 Browse/Stats 按钮可达，完整 sourceId 路由，无 Legacy 回退 |
| R6 导入 commit-last | authority staging 起始、`publishFromProjection` 后 visibility active；向导不抢 scope |
| R7 Android turna-migration-v1 导入器 | `TurnaMigrationImporter`（fail-closed 校验/事务/Legacy 行只入 pending）+ 设置页独立入口；export→import 往返测试 |
| R8 路由守卫 + 门禁 | `DiagnosticsReleaseGuard`（release+深链）；analyze 0 error、全量 1825/0、golden 4/4、arm64 APK 55.8MB（sha256 见 cutover-once/apk-sha256.txt） |

### 2026-08-24 及更早（原 Done 表）
|---|---|
| W0 原子导入计划 / Legacy 新写 fail-closed | `AnkiImportExecutionPlanner` + 向导 `_plan` 贯穿 pick/commit；Official-first 不得写 Legacy NoteStore；flag-off / `legacyMirror` fail-closed 零写入 |
| C3 Official-first 编排抽出 | `OfficialAnkiOfficialFirstService` 承载 saga / migration / preview / publish；向导只做 step UI 与 mapping。向导仍约 3400 行（C3 remainder：Legacy preview 未拆） |
| C5 死路径 | `officialFirstImportEligible` / `official_first_import_policy.dart` / `OfficialAnkiUserMigrationSaga` 已删；迁移预览无 stub cutover 按钮；用户可见 HarmonyOS 文案改为「仅旧版导入源」 |
| C4 配置面坍缩 | `OfficialAnkiFeatureFlags.fromEnvironment` 不再读 10 个能力 dart-define，生产 bundle 恒为 Official Android；opt-in 仅 diagnostics / reviewer diagnostics / migrationPilot / courseGrades / legacyMirror；`TURNA_OFFICIAL_ANKI_CUTOVER` 仍是暂停闸。Gray cohort 已退出 planner。`officialCapable` 改名为 `schedulerRuntimeAvailable`，不再冒充 owner。 |
| W8 可恢复单来源 Saga（§12.4） | `OfficialLegacySourceMigrationSaga` + `OfficialLegacyMigrationDriver`（census `cleanLegacy` 入队；需用户确认调度策略，启动不自动切 owner） |
| W8 调度策略用户可见三选一（禁止静默 reset） | `LegacyAnkiSchedulingPolicy` + `userVisibleLabel/Description`；无 lossless map 时要求 `policyConfirmedByUser` |
| W8 journal resume / rollback 单测 | `test/application/anki_official/official_legacy_source_migration_saga_test.dart`；输出 `/tmp/grok-goal-69bb594208d5/implementer/migration-legacy-retirement.txt` |
| W9-A（停住 Legacy 新写产品选择） | W0 fail-closed + architecture guards；见 HOLD 文档 |
| W9 §13.3 CI 门禁补强 | `anki_unification_architecture_guard_test.dart`：planner/`legacyOnly`、Official 禁 `ensureWord/updateReview`、unsupported platform 指针 |
| W9 物理删除 HOLD 书面落盘 | `34-w9-legacy-deletion-hold.md`（2026-08-24） |
| W10 文档入口收口 | 本目录 `README.md` 以 doc 34 为唯一活跃施工入口；31/32/33 标注由 34 接管 |
| W3 census / reconciler + journal | 分类器 + `JoinedOfficialAnkiSourceEvidenceReader`（Drift ∪ catalog，按 hash/id）；`OfficialAnkiStartupCensus` 启动只读 collect + journal `scanned`（幂等）。**不**自动改 owner |
| W5 基础骨架（非产品验收） | 共享 host 已能调用 `showAnswer` 并提交 Official scheduler；但 formal review 仍有 HTML 降级、固定队列 stale、Review All 单来源和六集合 due 缺口，返工见 remaining R2/R3 |
| W6 course = practice/introduction | `AnkiStudySessionHost.itemForCourse` + `official_course_practice_introduction_test.dart` |
| OHOS product target / patches removed | `ohos/` absent; `tool/apply_patches.sh` / `tool/patches/` absent; ADR 0041 |
| OHOS EOL ADR | [ADR 0041](../decisions/0041-ohos-product-eol.md) |

## Held（不得在本会话勾选完成）

> 2026-08-25 更新：原 Held 表中 Course scope、正式复习保真、Review All、六集合 due、W8 owner cutover、Browser/Stats 入口、Android 迁移包导入七项的 host 侧实现已由一次性施工关闭（见上表）；下表为**仍 Held** 的项。

| 项 | 原因 |
|---|---|
| 一个正式 release 观察（G5） | 日历/发布证据，单会话无法诚实完成 |
| W9-B..E Legacy 物理删除 / schema drop | 依赖 G5；见 HOLD |
| §19「Legacy importer/scheduler/schema 按 W9 分波删除」 | 显式未勾选 |
| 全量设备/release 真机闭环证明 | 本会话未伪造设备证据 |
| OHOS 用户完成数据出口 | 导出器/导入器均已落地（Android 导入入口可用）；外部事实未发生：无 sunset 真机、无书面豁免（R7-1 二选一未决） |
| release 真机矩阵（干净安装 / 升级安装 / 迁移包） | host 门禁全绿但无设备会话；不以 widget test 替代（plan 34 §4.4） |
| 真机 reimport / Browser/Stats/Media / 强杀恢复验证 | 同上，待设备矩阵 |
| 存量用户跑批 / owner 切换 | W8 driver 可入队 `cleanLegacy`；未对真实用户库执行 |
| OHOS 树物理删除 | 已完成（`ohos/` absent）；历史 archive 保留 |

## Android ABI packaging

Doc 34 §14.2 option 1: **arm64-v8a only** for Official native (`libturna_anki.so`).
Release command: `flutter build apk --release --split-per-abi --target-platform android-arm64`.
A fat multi-ABI APK without matching `.so` is forbidden (fail-closed, never Legacy fallback).

## Accurate status line

> 验收 NO-GO；Official Anki 迁移中：一次性代码收口（R0–R8 host 侧）已完成并全绿（analyze 0 error / 全量 1825:0 / golden 4:4 / arm64 APK 55.8MB / native pin+重建），形成**生产候选**；尚未真机验收（§12 矩阵未跑），外部事实（OHOS sunset/豁免、存量用户处置、Legacy 零新写观察期）未发生，W9 继续 HOLD。不得写「迁移完成」。
