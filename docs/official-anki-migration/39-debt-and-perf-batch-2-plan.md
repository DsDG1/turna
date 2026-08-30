# 39 — Anki 集成减负与性能批次二（死码二批 / 契约单表化 / DTO codegen / 传输层折叠 / Rust 收敛）

> 状态：**已登记待施工（2026-08-30 两轮全量复核后成稿；P1–P6 未开工）**。
> 范围：六个独立施工包 P1–P6：①Dart 死码删除二批（~2,000 行：孤儿 UI、死编排路径、零引用方法）；②契约表面单表化与 capabilities/VERSION 对拍闭环；③DTO codegen 迁移（宽松类先行）；④engine 传输层折叠与 worker 统一消息协议；⑤import/migration 域状态机与重复减负；⑥Rust 桥接单表化、样板收敛与测试治理。**不改变**渲染保真、调度语义、备份流程、collection 数据所有权、camel/snake 双键兼容输出。
> 前置阅读：[38](./38-debt-and-perf-batch-1-plan.md)（批次一已施工范围与 §11 批次二候选清单——本计划即其落地版并扩入新发现）、[35](./35-duplicate-legacy-layer-cleanup-plan.md)（迁移域删除时点）、[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)（契约与发布口径）。
> 铁律：**每个施工包独立 commit、独立可回滚**；**本机（Windows 开发机）无 cargo/protoc（doc 37 §10 / doc 38 铁律同记），P6 全部 Rust 改动必须在具备 Rust 1.97.1 + protoc 31.1 的主机通过 `cargo test -p turna_anki_bridge` + `gen_fixtures` regen 后方可合入**；契约 minor 逐次递增、号码永不复用（operations.md append-only 政策）；doc 38 §12.4 的工具链主机门禁未解除前，发布口径维持 NO-GO，本批 Rust 包与其同批过闸。
> 证据口径：本计划全部 file:line 于 2026-08-30 对照工作树经第二轮独立复核（含 lib+test 双侧 grep 取证）；个别行号施工时可能有 ±1~10 漂移，按 doc 38 §13.2-6 惯例不回写。

## 0. 一句话

把 doc 38 §11 留下的结构性债务（DTO 样板、操作表多处事实源、adapter 纯转发、错误模型多套、envelope 多重编解码）连同本轮新发现的死码（孤儿复习页 835 行、统一导入 legacy 死路径 ~250 行、engine 层零引用方法等合计 ~2,000 行）按「先删死码 → 契约表面单表化 → DTO codegen → 传输层折叠 → Rust 收敛」的依赖顺序落成六个独立可回滚的施工包，全部以「不改功能效果」为界，行为修复与产品决策项单列不混入。

## 1. 背景与证据摘要

分析覆盖：Rust 桥接（`native/turna_anki_core/bridge/src`，7,077 行——批次一后净增 ~660 行）、Dart official 层（`lib/application/anki_official` + `lib/views/anki_official` + `lib/application/anki_import` + `lib/views/anki` + `lib/data`，~40,900 行/168 文件）。两轮分析：五个分域代理全量扫描 + 对驱动大删除的声明逐条独立 grep 复核（本节末尾为复核修正记录）。

关键证据（均已核实）：

| 证据 | 位置 |
|---|---|
| 孤儿复习页无生产 push、无深链；3 个测试文件 4 处直接 pump | `official_anki_review_page.dart`（612 行）+ `official_anki_practice_review_surface.dart`（223 行，仅被该页 import）；pump 点 `official_anki_formal_review_ack_test.dart:77,231`、`official_anki_practice_ack_test.dart:107`、`official_anki_scheduler_p4_test.dart:339` |
| 迁移预览簇全树零引用（连测试都没有） | `official_anki_preview_loader.dart`（127 行）、`official_anki_migration_preview_page.dart`（92 行，路由注册 `routing.dart:85`）、`LegacyAnkiCensusService`（`official_anki_census.dart:125-171`） |
| unified 编排器 legacy 路径死：`UnifiedAnkiImportRequest(` 生产零构造（17 处命中全在 test）；生产 5 文件只用 `publishFromProjection`/`invalidate` | `unified_anki_import_orchestrator.dart`（448 行）；引用方 deck_manager / official_first_service / cleanup_service / reanchor / migration_coordinator |
| engine RPC 死方法：`listSources/listCards` 全部命中均为 DAO 接收者（`OfficialAnkiSourceDao(catalog).listSources` 等），engine 层零调用；`recoverUnfinished` 唯一命中是 worker 分支内部调 recovery service（传递性死亡）；`transport.openCollection` 零调用 | `session.dart:404-432,233-254,890-926`、`native_transport.dart:157-167` |
| `describeNextStates` 全 lib 命中均为 6 层实现本身 + 契约表，无业务调用方（预览标签实际用队列内 `card.labels`） | `domain/review/official_anki_review_ledger.dart:55-69` 为实际数据源 |
| capabilities 三份清单已漂移：Rust 35 项（含 RESTORE_BACKUP）、Dart productionNames 35 项、golden fixture **34 项（缺 RESTORE_BACKUP）**——fixture 为手工维护，2026-08-30 bump 1.10 时漏同步 | `contract.rs:109-145`、`official_anki_contract.dart:95-131`、`contract/fixtures/response_engine_info.json` |
| 错误解码表不对称：`officialAnkiErrorCodeFromName` 共 31 case，缺 `CAPABILITY_MISSING/NEEDS_RECONCILIATION/UNSUPPORTED_PLATFORM/LIBRARY_MISSING/SYMBOL_MISSING`，而 `_wireErrorCode` 会把对应枚举编码成这些串发出 → 跨 RPC 静默降级 `unknown` | `official_anki_errors.dart:70-137`、`session.dart:1006-1010` |
| 35 个 `*Id` 常量仅 3 个被使用（engineInfoId×2 / openCollectionId / getProjectionSchemasId）；session 直连 FFI 用裸魔法数 `6` 调 `LATEST_PROGRESS` | `official_anki_contract.dart:59-93`、`session.dart:263` |
| `AnkiImportSummary` 官方流程只填 7 个基础字段；10 个 Legacy parser 时代字段恒默认值，done 页无条件渲染其中两个 → 用户每次看到「0 结构化 / 0 保真」 | `official_first_anki_import_flow.dart:81-111`、`anki_import_done_step.dart:83-84`、`anki_import_wizard_state.dart:8-70` |
| DTO 手写样板：1169 行中 fromJson/toJson 块 514 行 + 构造器 238 行 ≈ 752 行，每字段出现 4 遍；codegen 基建已就位（pubspec 四件套、lib 下 16 个 `.g.dart`、anki 目录 0 个） | `official_anki_dto.dart`、`pubspec.yaml:21,49,51,61` |
| 传输层：`session_engine` 257 行 = 36 方法中 **29 纯转发 + 5 throw + 2 空 no-op**；worker 346 行绝大多数为 `_enqueue` 包装；一次 `answerCard` 同一 DTO 被构造 5 次（worker fromJson → 手工 toMap → 主 isolate 再 fromJson） | `official_anki_session_engine.dart`（通读全文复核）、`session.dart:489-491,1091-1101,1279-1338` |
| Rust：`as_mut().ok_or(STATUS_INVALID_STATE)` 31 处、`from_slice(request)` 25 处、`revlog_count` 在 answer_card 4 个调用点（:681,712,745,773）、`looks_like_envelope` 整包 parse 只为一个键、`let _ = OpenRequest{…}` 死语句、`STATUS_SCHEDULER_CAPABILITY_MISSING` 全仓仅「定义+两处映射」无返回点、gen_fixtures.rs:19 硬编码 BACKEND_COMMIT | `engine.rs`、`ops.rs`、`contract.rs:84-92`、`projection.rs:702-708`、`tools/gen_fixtures.rs:19` |
| 迁移协调器 `run()` 374 行、`_compatible` 恒 false（if 臂也是死代码）、journal `advance()/quarantineOpenOperation()` 生产零调用 | `official_legacy_migration_coordinator.dart:123-496`、`official_anki_operation_coordinator.dart:60-69`、`official_anki_source_reconciler.dart:725` |
| 测试腐坏：host_ffi 断言 `contractMinor anyOf(2,3,4,5,6)` vs 实际 1.10（本机无 .so 静默 skip，工具链主机必红）；6 处重复 native 守卫样板 | `official_anki_host_ffi_test.dart:44` |

**复核修正记录**（第二轮独立取证对第一轮代理报告的订正，后续引用均以本表为准）：

| # | 原说法 | 修正 |
|---|---|---|
| R1 | capabilities「Rust 34 / Dart 35 / fixture 34」 | 精确为 **Rust 35 / Dart 35 / fixture 34（缺 RESTORE_BACKUP）** |
| R2 | session_engine「28/34 纯转发」 | 精确为 **36 方法 = 29 转发 + 5 throw + 2 no-op**（603 行总数不变） |
| R3 | `catch (_)`「全域 43 处」 | 43 为 anki_official 目录口径；加 anki_import + views×2 + data 的广口径为 **51 处**，引用时注明口径 |
| R4 | host_ffi 守卫样板「7 处」、DECK_NOT_FOUND「三处 map_err」 | 样板精确 **6 处**；`.map_err(\|_\| STATUS_DECK_NOT_FOUND)` 精确匹配 **2 处**（`ops.rs:1285,1335`；第三处施工时再确认写法） |

## 2. 可行性复核结论与设计决策（对原始建议的修正/否决）

| # | 原建议 | 结论 | 依据 |
|---|---|---|---|
| V1 | 删 `describeNextStates` 时同步从 Rust capabilities 移除 | **否决**。Rust op 13 按 append-only 政策不动；只删 Dart 调用面（接口/转发×2/worker 分支/ffi/fake/productionNames 条目/idFor case）。P2 新增的对拍断言因此设计为**子集断言**（`productionNames ⊆ fixture capabilities`），删项不破断言 | `contract/compatibility.md` 号码永不复用；Rust capabilities 35 项含 DESCRIBE_NEXT_STATES |
| V2 | DTO 全量 codegen | **修正为分三类**。(a) 宽松解码类（`?? 默认值` 风格）直接迁 `@JsonSerializable`；(b) 带活 snake 别名的类（ImportLog/DeckNode/UndoStatus，活别名 ~13 处）以 `@JsonKey(alias:)` 试点一个类，生成代码与现解析**逐键对拍**（含缺字段语义），不一致则保留手写；(c) fail-closed 校验类（候选名单：ReviewQueue/ReviewQueueCard/AnswerResult/DeckCounts/StatsBatch/IntervalLabels/MutationResult，用 `officialRequire*` 抛错的）**保留手写**——codegen 默认填默认值会把「缺字段即错」静默变「缺字段用默认」，属行为改变 | `official_anki_dto.dart` 解析风格三分；`json_serializable` alias 支持需施工时按版本验证 |
| V3 | CardDescriptor 6 个 write-only 字段（queue/suspended/buried/flag/marked/tags）两侧同删 | **修正为只删 Dart 侧**。Rust 发射侧删除按 `compatibility.md` 属字段删除（wire 变更），留待下一次两侧同发布的 minor bump 顺带；本批在 operations.md 登记预留 | browser 中的 `suspended/buried/…` 命中是 browser 自己的筛选模型字段（`official_anki_source_aware_browser.dart:24-28,79-82`），非 descriptor 读取；两个 storage DAO 零命中 |
| V4 | 复习每卡 5 RPC 精简并入本批 | **否决，留批次三**。`getUndoStatus/congratsInfo` 每卡必拉的取消/按需化改变撤销按钮可用性时效，属 UI 可观察行为；本批只修「`_refreshStatus` 整体 `catch (_) {}` 吞错」（加日志不改控制流） | `official_anki_review_session.dart:327-348,427-433` |
| V5 | done 页删「0 结构化/0 保真」两行并入死码删除 | **拆出**。删字段（数据模型）不改行为；删展示行是 UI 变化，归 §9 行为修复/§10 知会项，与字段删除分开 commit | `anki_import_done_step.dart:83-84` |
| V6 | ops.rs 拆文件 | **否决单拆**。2,807 行中 49.5% 是测试；生产侧超 100 行函数仅 2 个且同属 answer 域。随 P6 answer 域重构顺带把 answer 族（~400 行）抽 `ops/answer.rs`，否则不动 | P6 复核 |
| V7 | 修 fixture 缺 RESTORE_BACKUP | **修正路径**：本机手改金子（doc 38 §12.3-10 先例）+ P2 落「fixture == 生成结果」对拍断言，工具链主机 `gen_fixtures` regen diff 收口；根因（三份手工清单）由 P2/P6 单表化+对拍闭环消除 | 本计划 §4/§8 |

其余可行性前提（已核实成立）：

| 前提 | 判定 | 关键事实 |
|---|---|---|
| codegen 基建零引入成本 | 成立 | `pubspec.yaml` 已有 freezed 3.2.5 / json_serializable 6.8.0 / build_runner 2.4.12 / freezed_annotation；lib 下已有 16 个 `.g.dart`；anki 目录 0 个 |
| isolate port 可传对象图，手工 Map 序列化非必需 | 成立 | Dart isolate SendPort 支持任意可发送对象；JSON 只在 FFI 边界（worker→Rust）需要；DTO 补 `toJson` 后 `_renderedCardMap/_avTagMap` 等 60 行手工镜像可删（无测试锁定该同步，属纯负担） |
| capabilities 数组顺序是金子敏感项 | 成立 | 现顺序非按 id 排（CREATE_BACKUP=17 排在 IMPORT=5 前）；单表化必须按当前输出顺序声明，用金子对拍兜底（serde_json 对象键规范化，仅数组序敏感） |
| 活 snake 别名清单可枚举 | 成立 | Rust 仅 4 个 handler 发 snake 键：import log（`ops.rs:342-351`）、deck tree（`:368-375`）、undo（`:795-802`）、progress（`:267-275`）；render/typed/projection/descriptor 全 camel——Dart 侧其余 ~42 处 snake 别名双读是死的（`question_text_without_av` 在 Rust 全仓 0 次出现） |

## 3. P1 — Dart 死码删除二批（~2,000 行 lib/ + ~500 行 test/）

沿用 doc 38 P1 手法：逐项 grep 留证（lib+test 双侧）、簇间独立 commit、architecture guard 增反复活规则。

### 3.1 簇 A：孤儿复习页（835 行）

删 `lib/views/anki_official/official_anki_review_page.dart`（612）与 `official_anki_practice_review_surface.dart`（223）+ 路由注册 + `diagnostics_release_guard.dart:21` 名单 + `routing.gr.dart` regen。

- **前置：迁移 4 个 pump 点**（formal_review_ack×2 / practice_ack / scheduler_p4）。迁移目标二选一，按断言语义就近选择：①共享会话宿主或 application 层 presenter；②若个别 ack 交互断言只能由该页承载，将页面**移入 `test/support/` 作为测试夹具**（从 lib/ 与路由删除，生产面归零）。逃生门②保证删除不被测试重写阻塞。
- 同步更新 `formal_review_launcher_test.dart:166-199` 的反引用断言与名单、`official_anki_architecture_guard_test.dart:21` 名单。
- `official_anki_reviewer_stage/view` **保留**（reviewer_page 仍在用，见 §14 B1）。

### 3.2 簇 B：迁移预览簇（~266 行，doc 38 P1-A 连带漏网）

删 `official_anki_preview_loader.dart`（127，全树零引用）、`official_anki_migration_preview_page.dart`（92，唯一 pusher 是 P1-A 已删的 internal page）、`LegacyAnkiCensusService`（census.dart:125-171，从未实例化）。连带：`routing.dart:85` 注册、guard 名单 `:22`、`official_diagnostics_release_guard_test.dart:20`、`official_anki_p5d_routing_test.dart:757,799` 两行路径断言。**保留** `LegacyAnkiCensusReport`/`DatabaseLegacyAnkiCensusReader`（saga/coordinator 在用）。

### 3.3 簇 C：unified 编排器 legacy 死路径（~250 行）

`UnifiedAnkiImportRequest` 生产零构造；删 `begin()/finalize()/importPackage()/_persist()/_hashExists()/placementCount()/reset()` 及 `persistedOwnerIsOfficial:false` 分支与其测试缝（`lookupByHash/persistIdentity`），类瘦身为「publishFromProjection + invalidate」。测试处置：`unified_anki_import_orchestrator_test.dart`（306 行）删死路径用例；`_inventory_test.dart`（163 行）整文件删；`anki_import_execution_plan_test.dart:150` 改用 planFor 断言。

### 3.4 簇 D：engine 零引用方法（~150 行 + worker 分支 37 行）

删 `OfficialAnkiSession.listSources/listCards`（含 worker 分支 `session.dart:890-926`）、`recoverUnfinished`（`:233-254` + worker 分支 `:733-739`）、`OfficialAnkiNativeTransport.openCollection`（`:157-167`）及 `_engineOpen` 残留。连带删接口（`engine.dart`）、session_engine 转发、worker 转发、fake 实现的对应方法。**注意**：删除前按方法名 grep 排除 DAO 同名方法干扰（本计划 §1 已核对：全部命中均为 DAO 接收者）。

### 3.5 簇 E：describeNextStates 死 RPC 链（~120 行 Dart 面）

删 Dart 侧全链（engine.dart / session_engine / session 主侧+worker 分支 / ffi / fake / productionNames 条目 / idFor case）。Rust op 13 与 capabilities 不动（§2 V1）。

### 3.6 簇 F：data/domain 死成员（~465 行）

| 目标 | 位置 | 证据 |
|---|---|---|
| `AnkiUnificationDao.introducedKeys/countByStatus/countIntroducedForSource`（零引用）+ `introductionState/deleteProjectionIdentityByCourseId`（仅测试） | `anki_unification_dao.dart:111-189,55-109,324-338` | 逐方法 grep；`introductionState` 8 处命中全在 `imported_history_introduction_test.dart` |
| `AnkiAudioResolver` staging/swap 家族 + `AnkiMediaSwapReceipt` | `anki_audio_resolver.dart:34-193,291,344`（copyMedia/stagingImportId/swapStagedMedia/rollbackMediaSwap/finalizeMediaSwap/copyMediaFiles/buildAssetPath） | 服务 doc 35 L1 已删的 Legacy 原地重导入流；生产零调用，仅 `anki_audio_resolver_copy_media_test.dart` 与 `anki_media_delete_test.dart:212-319` |
| `CardIntroductionRepository` 接口 + host/controller 可空字段 + 2 个测试 fake | `card_introduction_state.dart:65-78`、`study_session_controller.dart:15,27,204-249`、`anki_study_session_host.dart:18,24,152,162` | 生产两个构造点（`lesson_viewmodel.dart:732`、`anki_review_session_page.dart:329`）均不传；真正引入通道是 `CardIntroductionStore`（6+ 生产调用点） |
| 向导死部件 `AdvancedOptionsCard/PreviewField/ReasonDisclosure` | `anki_import_wizard_widgets.dart:522-650` | 全树零引用（legacy 预览/映射编辑对话框遗留） |

### 3.7 簇 G：零散死符号与注释订正（~150 行）

`AnkiSourceRoute`+`routeFor()`（engine_kind.dart:29-37,89-108）、`AnkiImportCompletion` typedef、`OfficialAnkiOfficialFirstService.importAndRecord`、`OfficialAnkiRecoveryService.decide()`（纯委托）、`Saga.isCleanupAfterReleaseMarked`、`StartupCensus.lastReport`、`AnkiImportDependencies.ankiLiteThreshold/dailyNewLimit`、`JournalDao.quarantineOpenOperation`、`AnkiImportRecord.storedCardCount/indexedCardCount`、`anki_owner_authority_dao.writeFence()` 读访问器、`OfficialAnkiCoordinator._compatible`（恒 false，`acquire` 直接 throw）；`ListOfficialAnkiSourceEvidenceReader`（自认测试夹具）移 `test/`；`parseRecordedKind` 双实现合一。注释订正 3 处（`anki_html_card_view.dart:26-27,389`、`domain/course/interaction.dart:183` 引已删类；source_management_page:183 引已删 internal page）。

### 3.8 反复活守卫

architecture guard 增规则：「孤儿复习页 / preview_loader / UnifiedAnkiImportRequest / audio staging 家族保持删除」（仿 doc 38 P1/35 L1 模式）。

## 4. P2 — 契约表面单表化与对拍闭环（纯 Dart + fixture 手改）

1. **四表合一**：`official_anki_contract.dart` 的名称表（:23-57）+ ID 表（:59-93）+ `idFor` switch（:133-211，79 行）收敛为一张 `const Map<String, int>`（~40 行替代 ~150 行）；**删全部 `*Id` 常量**（仅 3 个在用：engineInfoId 改 `idFor(engineInfo)`，另两个测试引用同步改）；`session.dart:263` 魔法数 `6` 与 `'LATEST_PROGRESS'` 字面量改查表；fake 的 capabilities（`engine_fake.dart:113-142` 硬编码 28 项）改 `productionNames` 派生。
2. **对拍断言闭环**（新增单一「契约表完整性」测试，合并现有三处散落断言 `scheduler_p4_test:24-69` / `render_contract_test:13-22` / `contract_test:113-138`）：①`productionNames ⊆ fixture capabilities`（子集断言，容忍 Rust 侧多 op——删 describeNextStates 不破）；②fixture capabilities 项数 == Rust `contract/VERSION` 对拍 `kOfficialAnkiContractMajor.Minor`；③operations.md 对拍循环（已有）保留。Rust 侧全集断言（capabilities == name→id 键集）归 P6。
3. **死 snake 别名删除**（~42 处）：render（`dto.dart:329-359` 的 `question_html/latex_svg/is_empty/question_av_tags/typed_answer/template_ordinal/body_class` 等）、typed（`:244-272`）、projection（`:573-696`）、descriptor 组全部删；**活的 13 处保留**（import log 4 键 / deck tree 6 键 / undo 2 键 / progress，Rust 发射侧见 §2 前提表）。`operations.md:45-46` 的「DTO are camelCase」表述改注「以下 op 保留 snake 兼容键：…」。
4. **write-only 字段**：删 `OfficialAnkiCardDescriptor` 6 字段的声明+解析（Rust 发射侧留待下次 minor，operations.md 登记）；`OfficialAnkiProgress` 补 `fromJson`（或删 `current/total` 死字段），两处手解合一（`engine_ffi.dart:133-145` / `session.dart:256-277`）。
5. **小件**：`EngineInfo`/`EngineMeta` 四字段重复收敛（Meta 复用 Info 解析）；contract major 校验三重复制删 2 处（留 `EnvelopeResponse.fromJson` 一处）；删死 fixture `request_answer_card.json`/`request_get_review_queue.json`（零引用，停在 1.3）；**修 `host_ffi_test.dart:44` 腐坏断言**（`anyOf(2..6)` → `kOfficialAnkiContractMinor`）+ 6 处守卫样板提 `withNativeEngine()` helper。

## 5. P3 — DTO codegen 迁移（分三类，试点先行）

按 §2 V2 三类迁移 `official_anki_dto.dart`（1169 行）：

1. **试点**：选 1 个带活别名的类（`OfficialAnkiDeckNode`）验证 `@JsonKey(alias:)` 生成代码与现解析逐键对拍（含缺字段语义）；通过则 (a)+(b) 类全迁，不通过则 (b) 类保留手写。
2. **(a) 宽松类 ~15 个**迁 `@JsonSerializable`（`fieldRename: none` + 显式 name 保持现键名）。
3. **(b) 带活别名 3 个**（ImportLog/DeckNode/UndoStatus）按试点结论。
4. **(c) fail-closed 类保留手写**（§2 V2 名单），文件头注释声明豁免原因。
5. `OfficialAnkiRenderedCard.fromJson`（54 行，大头是死别名）在 P2 删别名后先瘦身，再决定是否 codegen。
6. **验收对拍**：以 `contract/fixtures/` 与 `test/fixtures/anki_official/` 金样为输入，新旧解析输出全等（新增 round-trip 测试，每个迁移类至少 1 例含缺字段/多余键边界）。

## 6. P4 — engine 传输层折叠与 worker 统一消息协议

1. **worker 统一消息协议**：session 主侧 30 个方法的手工序列化（`:148-604`）与 worker 侧 `handle`（`:659-997`，339 行）+ `dispatchOfficialAnkiScheduler`（`:1026-1277`，252 行）收敛为单一协议：每方法一行注册 `(op 名, 参数构造器, 结果构造器)`，worker 侧一张派发表。配合 P3 的 DTO `toJson`，删 `session.dart:1279-1338` 手工镜像序列化（`_renderedCardMap/_avTagMap` 等）与 17 处 `?? raw` 双形状防御（`Map<String, Object?>.from(raw['payload'] as Map? ?? raw)` 形态）。预期 session.dart 1338→~700、worker 346→~150。
2. **session_engine 定位收窄**：保留（它是 capability 门面：5 个 `throw _missing` + 2 no-op 是刻意的降级面），但把 29 个纯转发的维护成本写进类注释并纳入 worker 协议单表（转发方法由「接口必须实现」降至「单表一行」）；`_compatible` 恒 false 已在 P1 簇 G 删除。
3. **latestProgress/cancel 双实现合一**：control 直连路径与 worker 路径留其一（等价性已有测试），魔法数归 P2。
4. **吞异常加日志不改控制流**：engine 域 9 处 `catch (_)`（`review_session:432`、`home_due_sync:205,368`、`course_grades_bridge:48`、`session_cleanup:167,193`、`session:618`、`engine_ffi:90,506`）逐处加 `debugPrint('[OfficialAnkiXxx] …')`（项目已有日志惯例）；`_refreshStatus` 吞掉的恰是每卡必付的 2 个 RPC 的错误，日志是排障最低配。anki_official 目录其余 34 处同批处理，views/data 域 8 处列清单随批。
5. **测试**：新增 worker 协议 round-trip 测试（每 op 编解码一例，锁定统一协议不回归）；现有 host/scheduler/p4 点名测试全绿为门禁。

## 7. P5 — import/migration 域减负

1. **状态机死态**：删 `official_anki_import_state.dart` 15 枚举中 5 个零使用值（hashing/cancelRequested/failedAfterImport/recovering/rolledBack）与 `decideOfficialAnkiRecovery` 对应死分支（~40 行）；DAO CHECK 约束不动（旧库历史串兼容，parse orElse 兜底 needsReconciliation 已安全）。删向导 `progress` 字段/copyWith/进度条死 UI（`anki_import_screen.dart:200-204,255-259`，本就不显示）。
2. **`AnkiImportSummary` 死字段**：删 10 个恒默认字段 + copyWith 死参数（数据模型层，不改 UI；done 页两行恒 0 展示归 §9）。**顺带核对** `unitCount: 0` 硬编码（`official_first_anki_import_flow.dart:107`）——若 done 页展示单元数则一并列入 §9。
3. **重复合一**：`wireKeyForImportId` 三份（completion_coordinator 扩展 + screen 手写副本）收敛为扩展单份；`markFailedBeforeImport/markNeedsReconciliation` 除 nextState 外逐行相同 → 参数化合一；`engineForImport/reviewTargetForImport` 共享一次 `findByLegacyImport` 结果（router N+1）；`parseRecordedKind` 归 P1 簇 G。
4. **超长方法拆分**：coordinator `run()`（374 行）按状态段提取私有步骤函数，10 次手工 `findById` 重读收敛为 `reload()` helper——**行为等价重构，逐段对照 saga_test（665 行）/coordinator_test（344 行）安全网，分多个小 commit**。
5. **view_helpers 归位**：`officialRecognitionTriage`（阻断性业务判定）与错误映射移入 `application/anki_import/recognition/`，view_helpers 只留纯格式化；`_roleLabel/userFacingFieldName/officialRecognitionChipLabel` 硬编码中文迁 `AppStrings`（zh 为源语言，文案同值替换，行为不变）。
6. **可选**：`OfficialFirstAnkiImportFlow`（115 行纯转发）内联进 controller——若 P4 落地后层级感知成本已降，可推迟。

## 8. P6 — Rust 桥接收敛（本机静态编写，工具链主机验）

按风险从低到高四波，每波独立 commit：

**波 1（零行为风险，~300 行）**：删 `projection.rs:702-708` 死语句、`STATUS_SCHEDULER_CAPABILITY_MISSING` 常量+两处映射臂、`engine_arc` 别名统一 `slot`；`gen_fixtures.rs:19` 的 `BACKEND_COMMIT` 改用 build.rs 注入的 env（删本地常量）；STATUS/OP 常量分组排列；`projection.rs:330-338` 缩进错乱。

**波 2（编译器可验证的样板收敛）**：`parse_req/parse_req_or_default` helper 收敛 25 处 `from_slice(request).map_err(|_| …)` 与 6 处空请求默认值；`open_col()`（或 `require_open` 返回 collection）收敛 31 处冗余 `.ok_or(STATUS_INVALID_STATE)`；复制簇提取——`cid_search()`（2+1 变体）、`labels_json()`（2 份）、`SchedulingStates::pick(rating)` + `answer_with_queue_fallback()`（answer_ahead 手抄 answer_card 机制）、`after_mutation(engine, Page|Content)` 收尾样板 ~13 处。

**波 3（单表化 + 对拍，金子兜底）**：`OP_TABLE: &[(u32, &str)]` 单表（**按当前 capabilities 输出顺序声明**，§2 前提），`operation_name_to_id` 改表查找、`engine_info_payload` capabilities 由表生成、dispatch 保留 match 但加「表全覆盖」测试断言；错误表 `(status, code, message_key, recoverable)` 单表 derive `code_for_status/message_key_for_status`；Rust 侧新增全集断言 `capabilities 集合 == name→id 键集`；**错误码修正**：`ops.rs:1285,1335` 的 `.map_err(|_| STATUS_DECK_NOT_FOUND)` 改 `map_anki_error`（吞 rslib 任意错误误标 deck 不存在——错误码语义修正，登记于 §9）；`EnvelopeError.debug_details` 开始填充（wire 新增字段，向后兼容，随下次 minor bump 评注）。

**波 4（中风险，契约测试最厚区域逐步做）**：envelope `payload` 改 `Box<serde_json::value::RawValue>`（消除 clone+to_vec+re-parse 三连；`looks_like_envelope` 与正式 parse 合一，错误 status 序列逐一对照现有测试）；`render_card` 第三次 get_card 并入 `load_card_note_nt`、`question/answer` clone 改借用；`answer_card` revlog_count 单点化（pre 一次 + post 一次复用给三个消费点，语义与响应值不变）——**热路径，施工前先跑 host_metrics 留基线**；answer 域抽 `ops/answer.rs`（随本波顺带，§2 V6）。

**测试治理（独立 commit）**：`#[cfg(test)] mod test_support` 收敛四胞胎 temp-open/三胞胎翻页/双实现 fixture 路径（~200 行）；`import.rs:320-326` 的 `include_str!` 源码文本断言改行为断言；perf-spike（`host_metrics`/`import_100k`/abi 10 万次 alloc）标 `#[ignore]` + 文档化显式跑法——**必须在波 4 基线留存之后做**；`ops.rs:2733-2763` 手挑 19 名单改全集断言（波 3 落地后自然消解）。

## 9. 行为修复单列（不属于「不改行为」清理，各自独立 bugfix commit）

| # | 项 | 位置 | 性质 |
|---|---|---|---|
| F1 | 转义事故：未知错误时用户看到字面量 `${AppStrings.ankiImportFailedHuman}`（单引号内 `\$` 不插值，文件迁移脚本事故） | `anki_import_view_helpers.dart:78` | 用户可见 bug，修 + 补 fallback 分支测试 |
| F2 | done 页「0 结构化 / 0 保真」两行恒 0 噪音（及 §7.2 核对后的 unitCount 恒 0，若有展示） | `anki_import_done_step.dart:83-84` | UI 变化，需产品知悉后删行 |
| F3 | 错误解码表补 5 个缺失 case（capabilityMissing/needsReconciliation/unsupportedPlatform/libraryMissing/symbolMissing），跨 RPC 不再静默降级 unknown | `official_anki_errors.dart:70-137` | 纯收紧（unknown→精确码），随 P4 |
| F4 | DECK_NOT_FOUND 误映射修正（归 P6 波 3） | `ops.rs:1285,1335` | 错误码语义修正 |

## 10. 需负责人决策项（本批不默认做）

| # | 项 | 决策点 |
|---|---|---|
| D1 | reconciliation journal 只写不消费：启动 `persistScannedJournals` 无限累积 `scanned` 行（幂等键含计数，随复习变化产生新行），`advance()/quarantineOpenOperation()` 生产零调用 | 删写入（行为变化：不再累积）还是补消费方（W3 修复流水线是否仍规划）？至少在 doc 34 §18.3 登记边界 |
| D2 | F2 的 done 页 UI 变化 | 产品知悉后执行 |
| D3 | P4 中 `getUndoStatus/congratsInfo` 每卡必拉的按需化（本批明确不做，§2 V4） | 批次三排期与 UI 验收方案 |

## 11. 依赖与施工顺序

```text
P1（先行，纯删除缩表面积；簇 A–G 各自独立 commit）
 ├─ P2（依赖簇 G 的 Id 常量删除面；fixture 手改 + 对拍闭环）
 │    └─ P3（宽松类 codegen；受益于 P2 删死别名后的瘦身 RenderedCard）
 └─ P4（依赖簇 D/E 死方法先删，减少要折叠的面；F3 随批）
P5（簇 C 删除后的 import 域收敛；与 P2/P4 无文件冲突可并行）
P6（独立静态编写；波 4 基线 → 测试治理 → 合入待工具链主机，与 doc 38 §12.4 遗留门禁同批过闸）
F1–F4 行为修复各自独立 bugfix commit，不与清理包混提
```

## 12. 风险表

| 风险 | 等级 | 缓解 |
|---|---|---|
| 簇 A 删除被 4 个 pump 点阻塞 | 中 | §3.1 逃生门：页面可移 `test/support/` 作夹具，生产面归零不受测试重写进度拖累 |
| 死码误删（同名方法干扰） | 中 | 本计划 §1 已按接收者核对（listSources/listCards 均为 DAO）；施工时每项 grep 留证 + architecture guard 反复活规则 |
| codegen 语义漂移（缺字段默认值/别名） | 中 | §2 V2 三类分治 + 试点逐键对拍 + fail-closed 类豁免；金样 round-trip 测试 |
| capabilities 单表化改变数组顺序 | 中 | 按当前输出顺序声明 + 金子对拍断言兜底（§2 前提） |
| worker 统一协议引入编解码回归 | 中 | 每 op 一例 round-trip 新测试 + 现有 host/scheduler/p4 点名全绿门禁 |
| envelope RawValue 化改变错误 status 序列 | 中 | 逐分支对照 contract.rs:309-472 与 abi.rs 现有测试；波 4 单独 commit 可回滚 |
| answer/render 热路径改坏 | 中 | host_metrics 基线先行（doc 38 §11 纪律）；`#[ignore]` 化必须在基线之后 |
| P5 run() 拆分引入迁移回归 | 中 | 逐段对照 saga/coordinator 测试安全网，多个小 commit |
| 本机无 Rust 工具链 | 中 | 铁律不变：P6 静态编写 → 工具链主机 `cargo test` + regen 全绿才合入；Dart 包（P1–P5）不受阻 |

## 13. 验证与验收

```bash
# Dart 侧（本机可跑；基线 = doc 38 §13 验货后的工作树）
flutter analyze                      # 0 issues
flutter test                         # 全量；对照基线 28 例 Windows 环境失败集合（doc 38 §12.2 点名清单）零新增
# 点名门禁（每包施工后）
flutter test test/application/anki/official_anki_architecture_guard_test.dart
flutter test test/application/anki/formal_review_launcher_test.dart
flutter test test/application/anki_official/official_anki_projection_test.dart
flutter test test/application/anki_official/official_anki_source_aware_browser_stats_test.dart
flutter test test/application/anki_official/official_anki_scheduler_p4_test.dart
flutter test test/application/anki_official/official_anki_contract_test.dart
flutter test test/routing/official_diagnostics_release_guard_test.dart

# Rust 侧（工具链主机；P6 各波）
cd native/turna_anki_core
export PROTOC="$PWD/tools/protoc/bin/protoc" PROTOC_BINARY="$PROTOC"
cargo test -p turna_anki_bridge
cargo run --bin turna_anki_gen_fixtures   # regen + diff review（fixture 修 RESTORE_BACKUP 后 diff 应干净）

# Android（P6 涉 .so 的波次）
./build-android/build.sh
```

量化验收口径（施工时以实测量填）：

| 包 | 指标 |
|---|---|
| P1 | lib/ 净删 ~2,000 行、test/ 净删 ~500 行；flutter analyze 仍 0；被删用例逐条列出 |
| P2 | contract.dart 352→~200 行；新增契约完整性测试 1 个（合并 3 处散落断言）；fixture capabilities 34→35（补 RESTORE_BACKUP）后对拍断言全绿 |
| P3 | dto.dart 手写面 1169→~550 行；金样 round-trip 对拍全等 |
| P4 | session.dart 1338→~700、worker 346→~150；`answerCard` 全链 Dart 构造次数 5→2（FFI 边界 fromJson + 业务返回对象）；worker round-trip 测试覆盖全部保留 op |
| P5 | run() 374→分段函数；重复实现处数：wireKey 3→1、mark* 2→1、latestProgress 3→1 |
| P6 | 新增一个 op 的触点 7→1（Rust 单表 + Dart 单表）；`as_mut().ok_or` 31→0、`from_slice(request)` 25→~1；revlog_count 调用点 4→2 且 host_metrics 基线不劣化 |

## 14. 明确不做（留批次三及以后 / 已登记时点项）

- **复习每卡 5 RPC 精简**（§2 V4/D3）与 registry 句柄回收、buffer ABI 加固（需先探查再立批）。
- **`mem::take` 无锁 import**：doc 38 §2-V2 否决维持（worker 串行 + close 错配风险）。
- **camel/snake 双键输出**（`canUndo/can_undo`、deck tree、counts 四处）：刻意兼容行为，**防误删登记**，非重复代码。
- **两套 HTML 卡渲染栈合并**（正式复习 webview 栈 vs canonicalLink 预览 reviewer 栈 726 行）：待 P1 簇 A 删除孤儿页后评估 reviewer 栈剩余消费者，再定切换方案。
- **迁移域 ~3,100 行整体删除**（saga/reconciler/coordinator/dry_run/backup_manifest/census 大部/迁移中心页）：等 doc 35 的 W9-E schema drop + NoteStore 读退役 + 一个 release 周期 legacy 读计数为 0，本批不动。
- **浏览器/统计 legacy 读分支 + `AnkiNoteDao` 剩余读侧**：doc 35 §1.3 登记的推迟项，时点不变。
- **P3 对拍参照实现删除**（`query.rs mod reference`/`projection.rs reference_rows`，~165 行）：doc 38 §12.4-4 已登记 pin 刷新时删，不重复立项。

## 15. 施工记录（待填）

> 每包施工后按 doc 38 §12 格式补：commit 清单、验收实测（含基线对照）、偏差与增补、待办门禁。验货记录（§16）由独立审计按 doc 38 §13 口径执行。
