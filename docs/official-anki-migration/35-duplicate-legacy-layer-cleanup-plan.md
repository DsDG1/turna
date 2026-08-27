# 35 — Legacy 复刻层清理施工计划（L0–L3，只删官方已替代的重复实现）

> 日期：2026-08-27
> 关联：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) §13 / §19（W9）；[`34-w9-legacy-deletion-hold.md`](./34-w9-legacy-deletion-hold.md)（HOLD 已解除，2026-08-27）
> 状态：**计划（待施工）**。本文档是 doc 34 W9 的重切执行版：**只删"复刻层"，不动自研资产**。
> 总原则：判据只有一条——**这个文件是否在手写复刻 Anki 的语义**（解析 anki2 sqlite、模板/cloze 渲染、media IRI、type-answer、对 Anki 卡的调度写入）。是 → 官方 core 已替代 → 删；否 → 自研资产 → 保留（最多搬家）。

---

## 1. 目标与边界

### 1.1 删什么（复刻层，≈13,000 行生产代码 + ≈20,000 行测试）

| 子面 | 体量 | 被什么替代 |
|---|---|---|
| Dart `.apkg` 解析管线（22 文件） | ≈10,900 行 | `OfficialAnkiImporter.importFile`（rslib FFI），W8 迁移也走它（`official_legacy_migration_coordinator.dart:284`），不依赖 Dart parser |
| Legacy 复习装配 + Anki 写入面 | ≈2,500 行 | `OfficialFormalReviewCoordinator` + `OfficialAnkiReviewLedger` |
| 孤儿/死代码 | ≈800 行 | 无消费者（生产零引用，仅测试） |

### 1.2 留什么（自研资产，本计划全程不动其行为）

| 资产 | 位置 | 保留理由 |
|---|---|---|
| Turna FSRS/SM-2 引擎 + 队列体系 | `core/fsrs_engine.dart`、`application/srs_provider.dart`、`srs_queue_provider.dart`、`srs_tutor_provider.dart`、`grammar_review_provider.dart`、`data/srs_state_dao.dart` | 内置词汇/表达/语法复习、AI tutor 的事实源；与 Anki 无竞争。**`srs_states` / `review_events` 两张表永久保留**（清数据时只删 `wordId LIKE 'anki-%'` 的行，属于后续计划） |
| `TurnaReviewLedger` 本体 | `domain/review/turna_review_ledger.dart` | 词汇复习 `srs_review_screen.dart:81` 仍在用；只删其中的 `ensureWord`（Anki 卡注册入口，唯一调用方在 `study_ledger_adapters.dart:54`） |
| 共享会话基座 | `anki_study_session_host`、`study_session_controller`、`study_ledger_adapters`、`study_product_analytics`、`anki_review_content` | 官方复习的骨架本身是自研的 |
| 导入向导 UX 层 | `import_wizard/{anki_import_controller, anki_import_wizard_state, anki_import_dependencies, anki_import_view_helpers, question_type, notetype_mapping_util}` | 驱动官方导入流的产品 UX |
| 产品统计/错题生态 | `review_progress_provider`、`review_dashboard/*`、`memory_curve_provider`、insights/mistakes 页面 | 自研产品功能 |
| 备份/恢复 | `service/remote_backup/*`（VACUUM INTO 整库 + official catalog 分量） | 纯自研基建 |
| 护栏体系 | `AnkiImportExecutionPlanner` fail-closed 语义、`anki_legacy_write_fence`、`anki_owner_authority_dao` | 正是它们让删除安全；保留到 NoteStore 退役（后续计划） |
| 混合件 | `anki_import_dao`（官方 due/dashboard 读）、`AnkiDeckManager`（课程管理/官方清理面）、`AnkiNoteDao`（官方 browser 只读）、`anki_import_cleanup_service`（legacy 卸载清理） | 有活的生产消费者；拆分/瘦身属于 NoteStore 退役计划 |
| migration-only exporter | `application/migration/turna_migration_export.dart`、`anki_official/migration/official_anki_backup_manifest.dart` | W8 迁移窗口需要；读表不读 parser |

### 1.3 明确不做（后续另立计划）

- **NoteStore 读退役**：browser/stats 混合分支（`official_anki_source_aware_browser.dart:94` 的 `legacyNotes`）、`AnkiNoteDao`、fun_lab 的 `anki_cards_meta` 快照面、prerender cache 统计。
- **Schema drop（doc 34 W9-E）**：course.db 目前 **没有任何 tombstone**（代码事实），drop 迁移不存在；触发条件 = 迁移窗口关闭 + 一个 release 周期 legacy 读计数为 0。
- **`anki_deck_manager` / `anki_import_cleanup_service` 瘦身**：依赖上一条。

---

## 2. 波次总览与顺序依据

```
L0 死代码 ──► L1 解析侧删除 ──► L2 复习侧删除（W8 门禁）──► L3 共享件搬正 + 边界反转
（零风险）    （条件已满足）      （唯一有产品依赖顺序的波）      （纯移动，lib/application/anki 消失）
```

顺序依据（代码事实）：

- L1 **不需要等 W8**：生产 planner 在 `officialAndroid` 下已永不返回 `legacyOnly`（`anki_import_execution_plan_test.dart` 全矩阵钉死），legacy 导入流只剩 `allowLegacyOnly` 测试/止血入口；parser 不碰任何活数据。
- L2 **必须等 W8**：`official_anki_engine_kind.dart:84-107` 中 recordedKind == legacy 的源在**所有平台**（含非 Android）仍走 legacy 复习路径，是存量用户的活路径。
- L3 放最后：删除完成前不动文件位置，避免"先搬后删"的无谓 churn；L3 之后 `lib/application/anki/` 目录里不再有任何东西。

**全部波次均为 code-only 删除，不触碰任何数据库行与磁盘文件**——这是回滚方案的基石（见 §7）。

---

## 3. L0 — 死代码清除（零风险，随时可做）

删除生产零消费者的孤儿文件。**每个任务先跑前置校验 grep，确认命中为空/仅测试后再删。**

| 任务 | 内容 | 前置校验（必须为空或仅 test/**） |
|---|---|---|
| L0-01 | 删孤儿 unification 基建 5 文件：`application/anki/unification/in_memory_anki_unification_store.dart`(384)、`application/anki/anki_unification_migration.dart`(136)、`domain/anki/repositories.dart`(62)、`domain/anki/review_queue_snapshot.dart`(44)、`domain/anki/course_card_placement.dart`(101) | `grep -rn "in_memory_anki_unification_store\|anki_unification_migration\|review_queue_snapshot\|course_card_placement" lib --include="*.dart" \| grep -v 上述文件自身` |
| L0-02 | 删 `application/anki/anki_media_url_resolver.dart`(50，lib 内零引用) | `grep -rn "anki_media_url_resolver" lib` |
| L0-03 | 删对应测试：`test/application/anki/anki_unification_migration_test.dart`、`test/domain/anki/anki_unification_contract_test.dart` 及引用孤儿 store 的测试 | `grep -rln "InMemoryAnkiUnificationStore\|CanonicalAnkiRepository" test` |
| L0-04 | 改写 guard test（`test/application/anki/anki_unification_architecture_guard_test.dart`，下同）：① 删除 `Directory('lib/application/anki/unification')` 扫描项（:14）与 `anki_unification_migration.dart` 具名路径（:23）；② 新增**反复活断言**（沿用 :240-253 `official_first_import_policy.dart` 的既有手法）：上述 6 个文件 `existsSync()` 必须为 false | — |

**L0 验收**：`flutter analyze` 0 issue；全量测试通过（记录删除前后用例数差）；grep 断言 6 个文件无任何 lib/test 引用残留。
**预计净删**：生产 ≈780 行，测试 ≈1,500 行。

---

## 4. L1 — 解析侧复刻层删除（最大一刀，条件已满足）

### 4.1 删除文件（生产 ≈11,000 行）

`lib/application/anki/` 下：`anki_importer.dart`(855)、`anki_models.dart` + `.freezed.dart` + `.g.dart`(≈3,860)、`anki_deck_assembler.dart`(1,106)、`anki_card_adapter.dart`+生成文件(≈1,540)、`anki_organization_resolver.dart`(356)、`anki_render_policy.dart`(149)、`anki_card_html_renderer.dart`(219)、`anki_template_renderer.dart`(238)、`anki_type_answer.dart`(66)、`anki_sample_deck.dart`(103)、`anki_srs_migrator.dart`(312)、`card_recognition_pipeline.dart`(713)、`legacy_anki_import_executor.dart`(445)、`anki_media_reference_extractor.dart`(159)、`import_wizard/legacy_anki_import_flow.dart`(148)。

> 例外核对（删前确认仍成立）：`anki_canonical_card_loader.dart`、`anki_template_renderer`、`anki_type_answer` 被 `views/lesson/components/interactions/anki_html_card_renderer.dart`（生产视图，读 NoteStore）使用——**保留到 L2 一起删**（见 5.1），本波不删这三个文件中 lesson 仍依赖的部分；若 grep 证实 lesson 渲染器是唯一消费者且 L2 门禁已满足，可与 L2 合并执行。

`lib/views/anki/import_wizard/` 下：`legacy_anki_import_preview.dart`(338)、`anki_notetype_mapping_editor.dart`(522)。

### 4.2 连带改造（删除的编译依赖面）

| 任务 | 改动 |
|---|---|
| L1-01 | `views/anki/anki_import_screen.dart`：删 `importerForTest` 字段（:51）、legacy preview 分支（:360-370）、`_editNotetypeMapping`/`_onAiIdentify`（:386-437）、`SrsProvider`/`AnkiImporter`/adapter/models import；done 步的 `importLearningProgress` 取值改恒 false（legacy 概念） |
| L1-02 | `application/anki/import_wizard/anki_import_controller.dart`：删 `legacyFlow` 字段与构造（:38,:42）、`AnkiImportExecutionKind.legacyOnly` case（:128）、`loadSample`（:134-150）及全部 `LegacyAnkiImportPreviewModel` 分支（:364,:386,:452,:497,:509,:533,:567） |
| L1-03 | `anki_import_wizard_state.dart`：sealed preview 删 `LegacyAnkiImportPreviewModel` 变体（连带 screen :132-144 的 `_isSample`） |
| L1-04 | `anki_import_dependencies.dart`：删 `importerForTest`、`srsProvider` 等 legacy 依赖参数；`planFor` 直连 planner |
| L1-05 | 路由：删 `AnkiImportPage.startWithSample` 参数（唯一调用点 `course_management_page.dart:153` 已传 false，属死参数）→ 重新生成 `routing.gr.dart`（**不得手改生成文件**） |
| L1-06 | `anki_import_facade.dart`：删 `AnkiImportDecision.legacy` 与 legacyOnly 映射（生产消费者 `official_first_service.dart:68` 只需 official/failClosed） |
| L1-07 | `anki_import_execution_plan.dart`：删 `AnkiImportExecutionKind.legacyOnly`、`allowLegacyOnly` 参数与 `_legacyOnly` 分支（parser 死后无 legacy writer 可选）；重写 `anki_import_execution_plan_test.dart` 矩阵为 officialFirst/failClosed/unsupported 三态 |
| L1-08 | `anki_official/official_anki_internal_page.dart`：删 legacy fixture drill（`AnkiImporter().parse` :633,:1002；`AnkiDeckAssembler().assemble` :699,:1062）。若整页只剩 legacy drill，则整页删除并同步 `routing.dart`、`developer_settings_page.dart` 入口与 guard test allowlist（:262-264）；若保留官方诊断段，仅剥离 legacy 段 |
| L1-09 | `anki_import_platform_io.dart` 拆分：`ankiHashFileSha256`/`ankiExtractArchiveToDisk`（`service/remote_backup/*` 三处在用）迁至中立位置（建议 `lib/service/remote_backup/archive_io.dart`）；sqlite 读取部分随 parser 删除 |
| L1-10 | 删测试：`test/anki/**`（13 文件）、`test/application/anki/**` 中 parser/wizard-legacy 用例、internal page 用例、facade legacy 用例 |

### 4.3 guard test 更新（L1）

- 删 :164-195（legacy flow/executor 断言）、:385-401 行数门禁中的 `legacy_anki_import_preview` / `legacy_anki_import_flow` 条目。
- 新增反复活断言：`lib/` 全树不得出现 `AnkiImporter`、`AnkiDeckAssembler`、`LegacyAnkiImportExecutor`、`AnkiCardAdapter`、`LegacyAnkiImportFlow` 符号（沿用 :311-329 `OfficialAnkiHomeDue` 的全树扫描手法）。
- `anki_official 不得 import legacy writer` 断言（:255-281）保留，internal page allowlist 视 L1-08 结果处理。

**L1 验收**：`flutter analyze` 0；全量测试 + golden 4:4 通过并记录用例数变化；arm64 release APK 构建成功并对比尺寸（预期略降，parser 为 AOT 内纯 Dart）；反复活 grep 断言进 CI。
**回滚锚点**：本波合并为独立 PR，revert 即恢复（无数据迁移）。

---

## 5. L2 — 复习侧复刻层删除（W8 门禁波）

### 5.1 进入门禁（全部满足才开工）

1. **W8 存量收口**：`anki_course_sources` / owner authority 查询 legacy-owned 源计数 = 0（`backend_kind = 'legacyTurna'` 无活行），或负责人书面决策"legacy 源改 fail-closed 只读"；
2. rollback / restore / uninstall drill 收据（沿用 doc 34 §13 口径）；
3. L1 已合入。

### 5.2 删除清单（生产 ≈2,500 行）

| 任务 | 内容 |
|---|---|
| L2-01 | 删 `application/anki/anki_review_assembler.dart`(493)。连带：`views/anki/anki_review_screen.dart` ≈12 处 `AnkiReviewAssembler.importIdFromSectionId` 调用（:99-583）——该 sectionId→importId 解析仍是官方路由需要的纯函数，**先迁到** `formal_review_launcher.dart`（或独立 util）再删类 |
| L2-02 | `views/anki/anki_review_session_page.dart`：删 legacy 运行时分支（:227-296：`SrsProvider` + `AnkiNoteDao` + `AnkiReviewAssembler.assembleReviewBatchAsync` + `TurnaStudyLedger`），页面只保留官方 loader 一条路 |
| L2-03 | `application/anki/study_ledger_adapters.dart`：删 `TurnaStudyLedger` 适配器（官方 `OfficialAnkiStudyLedger` 保留）；`domain/review/turna_review_ledger.dart` 删 `ensureWord`（:21，删除后无调用方；**类本体保留**——词汇复习在用） |
| L2-04 | 删 lesson 保真渲染族：`views/lesson/components/interactions/anki_html_card_renderer.dart`(410)、`application/anki/anki_canonical_card_loader.dart`(99)、`anki_card_html_renderer.dart`、`anki_template_renderer.dart`、`anki_type_answer.dart`（若 L1 已删则跳过）；连带 DI 注册 `di/renderer_module.dart`、`injection.config.dart` 中对应项重新生成 |
| L2-05 | `anki_deck_manager.dart`：解除 `AnkiReviewAssembler` 依赖（卸载路径改直连 `AnkiNoteDao`，行为不变） |
| L2-06 | 删/改测试：session page legacy 分支用例、assembler 单测、lesson 渲染器用例；`srs_review_screen`（词汇）用例**不动** |

### 5.3 guard test 更新（L2）

- 新增反复活断言：`lib/` 不得出现 `AnkiReviewAssembler`、`TurnaStudyLedger`；`anki_review_session_page.dart` 不得 import `SrsProvider`/`AnkiNoteDao`。
- `official owners do not call ensureWord` 断言（:283-307）保留并升级为全 lib 禁 `ensureWord`（该方法已不存在）。

**L2 验收**：同 L1；另加真机/桌面冒烟——官方源复习全流程、非 Android 官方源复习 fail-closed 提示（`AnkiOfficialReviewGate`）。

---

## 6. L3 — 共享件搬正 + 边界反转（纯移动，净零行）

L0–L2 之后，`lib/application/anki/` 剩余文件 = 纯自研资产。整波为 `git mv` + import 更新 + codegen 重跑，**不改任何行为**。

| 现位置 | 目标位置 | 说明 |
|---|---|---|
| `anki_study_session_host`、`study_session_controller`、`study_ledger_adapters`、`study_product_analytics`、`anki_review_content` | `lib/application/study_session/`（新建） | 双引擎共享会话基座，名字摘掉 anki/legacy 双重含义 |
| `formal_review_launcher`、`official_formal_review_production_loader`、`official_study_batch_assembler`、`formal_review_source_coordinator` | `lib/application/anki_official/review/` | 官方复习入口族 |
| `card_introduction_store`、`card_introduction_eligibility` | `lib/application/anki_official/`（engine/ 或新建 introduction/） | 官方 due 链依赖 |
| `unified_anki_import_orchestrator` | `lib/application/anki_official/import/` | `publishFromProjection` 是官方导入收尾 + W8 cutover 挂钩 |
| `card_presentation_policy` | `lib/application/anki_official/projection/` | 官方 projection payloads 在用 |
| `anki_deck_manager` | `lib/application/anki_official/` | 课程管理/官方清理面 |
| `import_wizard/` 剩余共享件（controller/state/deps/helpers/question_type/notetype_mapping_util/official_first_anki_import_flow） | `lib/application/anki_import/`（整目录迁出） | 向导 UX 层 |
| `domain/anki/` 共享模型（`study_models`、`canonical_card_key`、`card_presentation`、`card_introduction_state`、`presentation_receipt`、`objective_outcome`） | **原位保留** | 该目录本就是共享 domain；L0 删掉孤儿后即干净 |

**L3 收尾（边界反转）**：guard test 新增终态断言——`Directory('lib/application/anki')` 与 `Directory('lib/application/anki/unification')` **不得存在**；:17-27 具名路径清单更新为新家；`anki_unification_architecture_guard_test.dart` 更名为反映其终态职责（官方边界 + 反复活守卫）。

**L3 验收**：`flutter analyze` 0；全量测试通过（用例数不降）；`git diff --stat` 显示以 rename 为主；APK 尺寸不变。

---

## 7. 回滚方案

- **所有波次均为 code-only PR，零数据迁移、零 schema 变更、零磁盘操作**——回滚 = `git revert` 对应波次 PR。
- L2 的额外保障：删除前 legacy 数据（NoteStore 表、`anki_media/`、`srs_states` 的 anki 行）原样在库；revert 后 legacy 复习路径立即恢复可用。
- 每波必须独立 PR、独立验收记录，不得跨波混提（doc 34 维护规则：Legacy 删除不得作为顺手清理）。

## 8. 与 doc 34 W9 的映射

| doc 34 波次 | 本计划 | 差异 |
|---|---|---|
| W9-A（停新写） | 已完成（既有事实，不动） | — |
| W9-B（Turna FSRS 对 Anki 的 writer + assembler） | L2 | 引擎本体、`srs_states`/`review_events` 表明确保留（doc 34 原文亦为"通用 SRS 保留"） |
| W9-C（Dart parser + legacy import 分支） | L1 | migration-only exporter 保留；内部诊断页 drill 一并处理 |
| W9-D（browser/stats 分支 + 死 DI） | L0（死 DI/孤儿）+ L2-L4 部分（session 分支） | browser/stats 混合分支**推迟**到 NoteStore 退役计划（官方 browser 仍在只读 NoteStore） |
| W9-E（schema drop） | **不在本计划**，后续另立 | 代码尚无 tombstone；触发条件见 §1.3 |

## 9. 验证基线与证据记录（施工时逐波填写）

基线（2026-08-25 收据）：`flutter analyze` 0 issue · 全量 1852:0 · golden 4:4 · native 68:0 · arm64 APK 56.1MB。

| 波次 | commit | analyze | 全量测试（前→后） | golden | APK | 反复活断言 | 备注 |
|---|---|---|---|---|---|---|---|
| L0 | — 待填 | | | | | | |
| L1 | — 待填 | | | | | | |
| L2 | — 待填 | | | | | | 门禁收据链接 |
| L3 | — 待填 | | | | | | rename stat 摘要 |

> 规则：已执行任务必须填写实际 commit、命令与指标，不得只勾选（README 维护规则）。
