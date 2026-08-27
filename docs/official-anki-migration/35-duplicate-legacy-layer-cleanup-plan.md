# 35 — Legacy 复刻层清理施工计划（L0–L3，只删官方已替代的重复实现）

> 日期：2026-08-27
> 关联：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) §13 / §19（W9）；W9 HOLD 已于 2026-08-27 由负责人决策解除（原 HOLD 文件随解除删除，豁免决策记录见 [`34-cutover-receipt.md`](./34-cutover-receipt.md)「Held」表）
> 状态：**已施工（2026-08-27，L0–L3 四波各自独立 commit，见 §9 验收表）**。本文档是 doc 34 W9 的重切执行版：**只删"复刻层"，不动自研资产**。
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

> **施工时门禁记录（2026-08-27）**：第 1 条按"负责人书面决策"分支满足——2026-08-27 负责人决策解除 W9 HOLD 并豁免观察期证据（决策记录见 doc 34 收据），其语义即本计划 §5.2 的"legacy 源改 fail-closed 只读"；第 2 条 rollback/restore/uninstall drill 收据见 doc 34 收据 R0/R4/R6（backup/restore 测试、write fence、commit-last 恢复）；第 3 条 L1 已先行合入（commit `9cd7954c`）。

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

> **2026-08-27 施工环境说明**：本机（Windows host）复测基线为 analyze 4 个预存 info（`test/application/anki_official/official_anki_projection_test.dart` 的 unnecessary_const，非本次施工引入）与全量 31 个**环境性失败**（golden 字体渲染、Windows 文件名禁用 `?` 的 media 测试、本地日窗口查询等；基线文档的 1852:0 系原 macOS/Linux 施工 host 数字）。因此本次验收口径为：**失败集合与施工前基线逐项一致（零新增），analyze 不新增 issue**。

| 波次 | commit | analyze | 全量测试（前→后） | golden | APK | 反复活断言 | 备注 |
|---|---|---|---|---|---|---|---|
| L0 | `44c3797b` | 持平基线（4 预存 info） | 失败集不变（31 环境性）；受影响测试全绿 | 环境性不变 | — | ✅ 6 文件 + unification 目录不得存在 | 净删生产 759 行 / 测试 869 行 |
| L1 | `9cd7954c` | 持平基线 | 失败集与基线逐项一致（零新增） | 环境性不变 | — | ✅ 16 文件不得存在 + 5 类名全树禁用（去注释扫描） | 净删生产 8,055 行 / 测试 4,588 行；6 个渲染链文件按 §4.1 例外推迟到 L2 |
| L2 | `43bbf497` | 持平基线 | 失败集与基线逐项一致（零新增） | 环境性不变 | — | ✅ 8 文件不得存在 + AnkiReviewAssembler/TurnaStudyLedger 全树禁 + ensureWord 全 lib 禁 + session page 禁 SrsProvider/AnkiNoteDao | 净删生产 5,877 行（含 L1 推迟的 anki_models 生成件）/ 测试 1,088 行；门禁记录见 §5.1 |
| L3 | `d43d0314` | 持平基线 | 失败集与基线逐项一致（零新增） | 环境性不变 | 尺寸不变（纯移动，见 L2 后整包对比） | ✅ `lib/application/anki` 目录不得存在；guard 更名 official_anki_architecture_guard_test | 净变化 +8 行（纯 import 重写）；rename 占 diff 主体 |
| 终验 | L3 后 | 持平基线 | 失败集与基线逐项一致（31 环境性，零新增） | 环境性不变 | **arm64 release 53.0MB（基线 56.1MB，−3.1MB）** | ✅ 全部断言进 guard test 随全量执行 | 构建成功 `flutter build apk --release --split-per-abi --target-platform android-arm64` |

> 规则：已执行任务必须填写实际 commit、命令与指标，不得只勾选（README 维护规则）。

---

## 10. 施工实录：与计划的差异（2026-08-27）

计划是按当时代码写的；施工时逐项核对了真实依赖面，以下偏差全部有代码证据支撑：

### L0

- **`domain/anki/repositories.dart` 非纯孤儿**：`CardIntroductionRepository` 被会话基座（`study_session_controller` / `anki_study_session_host`）在用。处置：该接口**迁入 `card_introduction_state.dart`**（同域自然归宿），其余 4 个死接口（CanonicalAnkiRepository / CourseCardRepository / CardPresentationRepository / ReviewQueueRepository）随文件消亡。guard 反复活断言不变（`repositories.dart` 仍不得存在）。
- SQL 表 `anki_course_card_placements` 有生产读者（`official_anki_home_due_sync`）——本就只删 Dart 层，表不动，符合"零数据迁移"原则。

### L1

- **`question_type.dart` / `notetype_mapping_util.dart` 删除**（计划列为保留）：二者只服务于 legacy 预览/映射编辑对话框与识别管线；官方映射页（`official_anki_mapping_page`）用自有 `OfficialAnkiMappingSuggestion` 体系，不依赖 `NotetypeMapping`。legacy 面删除后二者成死代码，按"孤儿即删"处理。
- **`AnkiImportSummary` 迁入 `anki_import_wizard_state.dart`**（原定义在 `anki_deck_assembler.dart`）：官方流、完成协调器与 done 步共用。
- **`AnkiTemplate` 内联进 `anki_note_dao.dart`**：NoteStore 模板持久化（`AnkiNotetypeRecord.templates` 的 JSON 往返）仍需该形状；手写 const 构造 + fromJson/toJson 保持 JSON 兼容。
- **`anki_import_platform_io.dart` → `service/remote_backup/archive_io.dart`**：`ankiHashFileSha256`/`ankiExtractArchiveToDisk` 更名 `archiveFileSha256`/`extractArchiveToDisk` 迁至中立位置；sqlite 读取面随 parser 消亡；stub 文件一并删除。
- **internal page 保留**（非"只剩 legacy drill"）：剥离 `_seedP5cFixtureLegacy`、`_seedD4Legacy`、`_runD4FirstSource`、`_runD4MutationGt0Rollback` 及 4 按钮 + 死常量；官方诊断段（导入/预览/正式复习/迁移预览/Fixture 回滚演练）全部保留。副作用：P5C fixture pilot 演练不再有内置种子按钮，只能对真机上的真实 legacy 数据运行（dev-only 降级，可接受）。guard allowlist 相应收紧（internal page 不再豁免）。
- **执行计划三态化**：`legacyOnly`/`allowLegacyOnly`/`isSample`/`AnkiImportOwner.legacy`/`AnkiImportDecision.legacy`/`LegacyAnkiImportFacade` 全删；矩阵测试重写为 officialFirst/failClosed/unsupported。
- **连带死代码**：`anki_deck_manager.detectNewNotes`、`card_introduction_store.seedLegacyImport` 删除。

### L2

- **lesson learn 路径语义**（§5.2 L2-03 的隐藏依赖）：`itemForCourse` 原将 legacy 课程卡映射为 learn + turnaFsrs（由 `TurnaStudyLedger` 落笔）。writer 删除后改为**与官方一致的 practice/none**（翻卡 + introduction，不写 FSRS）——即门禁语义"legacy 源 fail-closed 只读"在课程学习面的体现；`lesson_viewmodel` 的 host 不再装配 turna 腿。
- **持久化 `AnkiHtmlCard` 兜底**（计划未列、防崩溃必需）：旧导入的 lesson 体与错题快照仍在 DB 里携带该类型，`lookupRenderer` 对未注册类型抛 StateError。新增 `anki_html_card_retired_renderer`（确认即过的占位卡，指向旧版兼容设置），避免存量数据闪退。类型本体保留——官方保真复习（`official_formal_review_coordinator` → `anki_review_content`）仍在用。
- **Review All 收敛**：`formal_review_source_coordinator.fromCatalog` 直接跳过 legacy-only 源（原第二分支发 legacy target，落进已删分支）。
- **session page fail-closed**：recorded-legacy 源 tap 进入页面后显示 fail-closed 错误面（`FormalReviewLauncher.failClosedMessage`），不再静默换语义。
- **deck_manager 死 quota 面删除**：`recordCardReviewed`/`recordCardUnreviewed`/`remainingForImport`/`newRemainingToday`/`reviewRemainingToday` 及日计数器在 session 分支删除后零消费者（全局限额 get/set 与 per-import 限额 DAO 面保留，设置页与牌组设置对话框仍在用）。
- **静态调用迁移**：`importIdFromSectionId`/`ankiPrefix`/`importIdFromWordId` 全部改指 `LegacyAnkiIdentifiers`（`official_anki_ids.dart`，官方前缀感知），比计划设想的"迁到 formal_review_launcher"更少改动。
- **保留 `itemFromReviewCard`**：纯映射（wordId→StudyItem），官方复习内容测试在用；其 learn/review 模式对 legacy id 产出 turnaFsrs owner，但已无生产路径 commit 之。

### L3

- **`anki_import_cleanup_service` 一并迁至 `anki_official/`**（§6 表未列，但终态断言要求 `lib/application/anki` 清空；该文件是 deck_manager 卸载路径的活依赖）。
- **`import_wizard/` 整目录迁至 `anki_import/`**，含 `anki_import_completion_coordinator` 与 `official_first_anki_import_flow`（表只列 7 件，实际全部迁出）。
- **guard 更名** `official_anki_architecture_guard_test.dart`，并新增 `Directory('lib/application/anki')` 不得存在的终态断言。
- 瘦身（deck_manager/cleanup_service 拆分）仍按 §1.3 属 NoteStore 退役计划，未做。
