# 34 — Cutover receipt（W8–W10 收口摘要）

> 日期：2026-08-24
> 状态：**验收 NO-GO；Official Anki 迁移中**（不得写「迁移完成」）
> 计划真源：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)
> 剩余波次：[`34-remaining-construction-plan.md`](./34-remaining-construction-plan.md)
> HOLD：[`34-w9-legacy-deletion-hold.md`](./34-w9-legacy-deletion-hold.md)
> OHOS EOL ADR：[ADR 0041](../decisions/0041-ohos-product-eol.md)（草案曾写 0038；0038 已占用）

---

## Done（本收口有仓库证据）

| 项 | 证据 |
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

| 项 | 原因 |
|---|---|
| 一个正式 release 观察（G5） | 日历/发布证据，单会话无法诚实完成 |
| W9-B..E Legacy 物理删除 / schema drop | 依赖 G5；见 HOLD |
| §19「Legacy importer/scheduler/schema 按 W9 分波删除」 | 显式未勾选 |
| 全量设备/release 真机闭环证明 | 本会话未伪造设备证据 |
| OHOS 用户完成数据出口 | 导出库存在；无 sunset 真机、无 Android zip 导入、无豁免 |
| Course scope / 课程选择 | Official sourceId 被截成 `src`；builtin scope 泄漏 Official Section；多来源折叠，当前 active scope 可能不在 courseEntries 中 |
| 正式复习保真与实时队列 | loader strip HTML；页面使用固定 StudyItem 数组；Scheduler 重排/重新插入后可能 stale |
| Review All | 当前只消费第一个 Official 来源，计数和实际复习集合不一致 |
| Exact due 六集合 | placement missing 非 fail-closed；retired 未接生产 reader；静态状态和 rollback 不完整 |
| W8 owner cutover | freeze 未覆盖全部 Legacy mutator；跨数据库顺序写不能称为原子事务 |
| W7 browser/stats 完整 Official 语义（forecast / bury / 无 engine 也可用） | 有 engine 时 Collection 搜索/render/suspend 已接线；无 engine 时 catalog 回退。Stats 无 forecast 不得 `metricsProven`。不是「未做」，也不是「完成」 |
| 存量用户跑批 / owner 切换 | W8 driver 可入队 `cleanLegacy`；未对真实用户库执行 |
| OHOS 树物理删除 | 已完成（`ohos/` absent）；历史 archive 保留 |

## Android ABI packaging

Doc 34 §14.2 option 1: **arm64-v8a only** for Official native (`libturna_anki.so`).
Release command: `flutter build apk --release --split-per-abi --target-platform android-arm64`.
A fat multi-ABI APK without matching `.so` is forbidden (fail-closed, never Legacy fallback).

## Accurate status line

> 验收 NO-GO；Official Anki 迁移中：Official-first/fail-closed、OHOS 主工程删除和 arm64 构建骨架可保留；course scope、实时保真复习、六集合 due、W8 owner cutover、Browser/Stats、OHOS 数据出口和发布证据必须按 remaining R0–R8 返工。不得写「迁移完成」。
