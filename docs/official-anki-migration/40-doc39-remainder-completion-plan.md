# 40 — doc 39 收尾施工计划（P5 余量 / F1 转义 bug / Rust 收敛四波）

> 状态：**部分收口（2026-08-30）：R1 / R2 / F1（R3）+ R4 波 1–3 + 测试治理已施工并记录（§11/§11.5）；R4 波 4 + perf-spike `#[ignore]` + debug_details 填充移交工具链主机会话（§11.5 执行清单）**。doc 39 的 P1 全簇、P2、P3、P4、F2、F3 及 P5 前半已施工并独立 commit（清单见 §1）；本计划把剩余未完成项整理为 R1–R4 + P6 五个独立施工包，口径与 doc 39 一致：**不改功能效果**的清理照旧，F1 是用户可见 bugfix 单列。
> 前置阅读：[39](./39-debt-and-perf-batch-2-plan.md)（原计划全文，本文只承接其未完成部分并携带施工偏差）、[38](./38-debt-and-perf-batch-1-plan.md) §12.4（工具链主机门禁）、[35](./35-duplicate-legacy-layer-cleanup-plan.md)。
> 铁律（继承 doc 39，不变）：**每个施工包独立 commit、独立可回滚**；**本机（Windows 开发机）无 cargo/protoc，P6 全部 Rust 改动必须在具备 Rust 1.97.1 + protoc 31.1 的主机通过 `cargo test -p turna_anki_bridge` + `gen_fixtures` regen 后方可合入**；契约号码 append-only；本机 Dart 包（R1–R4、F1）不受阻。
> 证据口径：本文 file:line 于 2026-08-30 对照 doc 39 施工后的工作树实测（P1–P4 改动已使部分行号较 doc 39 漂移，均以本文为准）。

## 0. 一句话

把 doc 39 收尾后剩下的四块落完：①P5 后半三个小重构（mark* 参数化合一、router N+1、coordinator `run()` 拆分与 view_helpers 归位）；②F1 用户可见的转义事故 bugfix；③P6 Rust 桥接收敛四波（本机静态编写 → 工具链主机验）；④合并 doc 37/38/39 三批 Rust 改动的工具链主机验证门禁。

## 1. 已完成基线（doc 39 已施工部分，验货依据）

施工分支 `p1-dead-code-cleanup`，2026-08-30，全部独立 commit：

| 包 | commit | 摘要 |
|---|---|---|
| P1-A | fa800c5a | 孤儿复习页 835 行移 test/support 夹具，生产路由/守卫面归零 |
| P1-B | 366a37a4 | 迁移预览簇删除（preview_loader/migration_preview_page/CensusService） |
| P1-C | ecb62ac4 | unified 编排器 legacy 死路径删除（448→165 行） |
| P1-D | 7b08fedb | engine 零引用方法删除（listSources/listCards/recoverUnfinished/openCollection） |
| P1-E | 98a7eba9 | describeNextStates Dart 面死 RPC 链删除（Rust op 13 不动） |
| P1-F | 337fc626 | unification DAO 死成员 / audio staging-swap 家族 / CardIntroductionRepository / 向导死部件 |
| P1-G | ab7e8d5f | 零散死符号 11 项 + 注释订正 4 处 + 反复活守卫规则 |
| P2 | e3615951 | 契约四表合一（~150 行→单 Map）+ fixture 补 RESTORE_BACKUP（35 项）+ integrity 对拍测试 + 死 snake 别名删除 |
| P3 | 30eaee7c | DTO codegen：12 个宽松类迁 @JsonSerializable + 金样边界对拍测试 |
| P4 | 65d03d5b | worker 统一消息协议（回执直传 DTO）+ F3 错误解码补 5 case + 47 处吞异常加日志 |
| F2 | 3a67faac | done 页「0 结构化/0 保真」两行删除 |
| P5 前半 | 2ef7081d | 状态机 5 死态/摘要 10 死字段/进度条死 UI/wireKey 三合一 |

验收实测（本机 Windows，施工后工作树）：`flutter analyze` **0 issues**；点名门禁（architecture guard / formal_review_launcher / projection / browser stats / scheduler_p4 / contract integrity / diagnostics guard / worker protocol / codegen parity / composition ×2 / host_ffi / session_lifecycle / scheduler_contract / ack×2 / recovery / orchestrator / p5d routing / render contract 等）全绿；全量套件结果记于 doc 39 §15。既存基线失败见 doc 38 §12.2 清单（28 例 Windows 环境预存），本批施工未新增失败。

### 1.1 施工偏差（承接至后续施工时必须知道的事实）

| # | 原计划说法 | 实测修正 |
|---|---|---|
| D-1 | §2 V3：CardDescriptor 6 字段（queue/suspended/buried/flag/marked/tags）两侧同删/仅删 Dart | **撤销删除**。source-aware browser 的筛选模型与行展示在读全部六字段（`official_anki_source_aware_browser.dart:270-274,372-381`），fake 引擎也以它们建模卡状态。无 wire 变更需登记 |
| D-2 | §2 V2/(b)：`@JsonKey(alias:)` 试点 ImportLog/DeckNode/UndoStatus | **试点失败**：json_annotation 4.9.0 的 JsonKey 无 alias 参数。(b) 双键读取类按逃生门保留手写，文件头已注明 |
| D-3 | §3.6：`AnkiUnificationDao.introductionState` 仅测试引用 | 实测被 **4 个测试文件**用作读回验证，保留；仅删引入 4 个零引用 DAO 方法 |
| D-4 | §4.1：fake capabilities 硬编码 28 项 | 已改为 `productionNames` 派生（单表化副产物），fake 与生产名表不会再漂移 |
| D-5 | §5.2：`unitCount: 0` 硬编码「若 done 页展示则列入 §9」 | 核对无任何展示位，无动作 |

## 2. R1 — P5 后半：import 域重复合一（两个小 commit）

1. **mark\* 双胞胎参数化合一**：`official_anki_import_orchestrator.dart:293,321` 的 `markFailedBeforeImport` / `markNeedsReconciliation` 除 nextState 字符串与返回的 `state` 外逐行相同 → 提取 `_markTerminal(OfficialAnkiAttemptRow attempt, OfficialAnkiSourceState terminal)`，两个公开方法变一行委托（recovery decide 的三个 action 仍各自命名，行为不变）。
2. **router N+1**：`official_anki_production_router.dart` 的 `engineForImport` / `reviewTargetForImport` 各自 `findByLegacyImport` → 提取共享的一次查询结果传入两者（方法签名加 `LegacyAnkiMigrationRow? row` 或提取私有 `_resolve(record)`，选择以测试改动最小为准）。

## 3. R2 — P5：coordinator `run()` 拆分与 view_helpers 归位

1. **`run()` 拆分**（`official_legacy_migration_coordinator.dart`，`run()` 自 `:123` 起约 374 行，文件 497 行）：按状态段提取私有步骤函数（freeze→backup→import→project→publish→activate 段各一），10 次手工 `findById` 重读收敛为 `reload()` helper。**行为等价重构**：逐段对照 `official_legacy_source_migration_saga_test.dart`（665 行）/coordinator 测试安全网，分多个小 commit，严禁顺手改判定。
2. **view_helpers 归位**（`anki_import_view_helpers.dart`，172 行）：`officialRecognitionTriage`（:30，阻断性业务判定）与错误映射移入 `application/anki_import/recognition/`，view_helpers 只留纯格式化；`_roleLabel`（:120）/`userFacingFieldName`/`officialRecognitionChipLabel` 硬编码中文迁 `AppStrings`（zh 为源语言，文案同值替换）。
3. **可选**（P5.6，若 R1/R2 后层级感知成本已降可推迟）：`OfficialFirstAnkiImportFlow` 115 行纯转发内联进 controller。

## 4. R3 — F1 转义事故 bugfix（独立 bugfix commit）

`anki_import_view_helpers.dart:78`：

```dart
return '\${AppStrings.ankiImportFailedHuman} (\${e.code.name})';
```

单引号内的 `\$` 不插值——用户在导入失败时看到字面量 `${AppStrings.ankiImportFailedHuman} (${e.code.name})`（文件迁移脚本事故）。修为正常插值：

```dart
return '${AppStrings.ankiImportFailedHuman} (${e.code.name})';
```

补 fallback 分支测试：构造 OfficialAnkiException 走 humanError 路径，断言文案含中文失败描述与错误 code，不含 `$` 字面量。

## 5. R4 — P6：Rust 桥接收敛（本机静态编写，工具链主机验）

原 doc 39 §8 四波计划**整体有效**，施工时点顺延至此。实测锚点（2026-08-30，较原计划登记的 31/25 有下降，系 P1–P4 删除传导致；以本文数字为准）：

- `as_mut().ok_or(STATUS_INVALID_STATE)` ops.rs **22 处** → 目标 0（`open_col()`/`require_open` 收敛）；
- `from_slice(request)` ops.rs **14** + import.rs **2** + engine.rs **1** = **17 处** → 目标 ~1（`parse_req`/`parse_req_or_default` helper）。

四波内容、顺序与红线不变，摘引如下（施工时以 doc 39 §8 原文为准）：

| 波 | 内容 | 关键红线 |
|---|---|---|
| 波 1（零行为风险 ~300 行） | 删 projection.rs 死语句、STATUS_SCHEDULER_CAPABILITY_MISSING 常量+两处映射、engine_arc 别名统一 `slot`、gen_fixtures BACKEND_COMMIT 改 build.rs env、STATUS/OP 常量分组、projection.rs 缩进 | 无 |
| 波 2（编译器可验证） | parse_req 25→17 处收敛、open_col 22 处收敛、cid_search/labels_json/SchedulingStates::pick/answer_with_queue_fallback/after_mutation 复制簇提取 | 编译器+现有测试兜底 |
| 波 3（单表化+对拍） | OP_TABLE 单表（**按当前 capabilities 输出顺序声明**）、错误表单表 derive、Rust 全集断言、DECK_NOT_FOUND 误映射修正（ops.rs `.map_err(\|_\| STATUS_DECK_NOT_FOUND)` 2 处改 map_anki_error，= doc 39 F4）、debug_details 开始填充 | 金子兜底；错误码修正登记 §9 F4 |
| 波 4（中风险） | envelope `payload` 改 `Box<RawValue>`、render_card 第三次 get_card 并入 load_card_note_nt、answer_card revlog_count 单点化（**热路径：先跑 host_metrics 留基线**）、answer 域抽 `ops/answer.rs` | 波 4 单独 commit 可回滚；`#[ignore]` 化必须在基线之后 |
| 测试治理（独立 commit） | `#[cfg(test)] mod test_support` 收敛、import.rs include_str! 文本断言改行为断言、perf-spike 标 `#[ignore]`+文档化、ops.rs 手挑 19 名单改全集断言（波 3 后自然消解） | — |

## 6. 门禁与决策项（不变，收口时执行）

1. **工具链主机**（doc 37 §10 + doc 38 §12.4 + 本文 R4 合并闸）：`cd native/turna_anki_core && PROTOC=… cargo test -p turna_anki_bridge` 全绿；`cargo run --bin turna_anki_gen_fixtures` regen diff review（P2 已手修 fixture RESTORE_BACKUP，diff 应为空或仅次序）。
2. **Android**：涉 .so 的波次 `./build-android/build.sh` smoke。
3. 决策项 D1（journal 只写不消费）/ D3（每卡 5 RPC 按需化，批次三）维持 doc 39 §10 原判，不随本重整改变。

## 7. 依赖与施工顺序

```text
F1（独立 bugfix，最先——用户可见）
R1（P5 后半两小项）→ R2（run() 拆分 + view_helpers；多小 commit）
P6 波1→波2→波3→波4→测试治理（静态编写即可开始，与 R1/R2 无文件冲突可并行；每波独立 commit）
工具链主机统一验：cargo test + gen_fixtures regen（三批同闸）→ Android build.sh
```

## 8. 风险表（仅新增/变化项）

| 风险 | 等级 | 缓解 |
|---|---|---|
| run() 拆分引入迁移回归 | 中 | 逐段对照 saga/coordinator 测试安全网；行为等价纪律；多个小 commit |
| F1 修改变更用户可见文案拼接 | 低 | 补 fallback 分支测试断言无 `$` 字面量残留 |
| Rust 实测计数与原计划漂移导致验收口径混乱 | 低 | 本文 §5 已给实测锚点；验收以「→0 / →~1」目标 + 测试全绿为准 |

## 9. 量化验收口径

| 包 | 指标 |
|---|---|
| R1+R2 | mark* 实现处数 2→1（委托不计）、findByLegacyImport 调用 2→1；run() 374 行→分段函数（单段 ≤80 行）；coordinator 文件行数下降且测试全绿 |
| F1 | 失败文案无 `${` 字面量；新增 fallback 测试 1 例 |
| P6 | 同 doc 39 §13 表（as_mut 22→0、from_slice 17→~1、revlog_count 4→2、新增 op 触点 7→1），host_metrics 基线不劣化（工具链主机） |

## 10. 明确不做（继承 doc 39 §14，全部维持）

复习每卡 5 RPC 精简（批次三）、mem::take 无锁 import、camel/snake 双键输出、两套 HTML 渲染栈合并评估、迁移域 ~3,100 行整体删除、浏览器/统计 legacy 读分支、P3 对拍参照实现删除（pin 刷新时点）。

## 11. 施工记录（2026-08-30，R1–R3 已施工——P6/R4 余留）

### 11.1 提交清单（独立 commit，按施工序）

| 包 | commit | 摘要 |
|---|---|---|
| F1（§4/R3） | 4d4e1f99 | 转义事故修复：`mapOfficialErrorToHuman` fallback 改正常插值；新增 `anki_import_view_helpers_test.dart`（fallback 语义 1 例 + 全 38 个 `OfficialAnkiErrorCode` 无 `${`/`\$` 残留断言 1 例） |
| R1-a（§2.1） | 65602e72 | `markFailedBeforeImport`/`markNeedsReconciliation` 提取 `_markTerminal(attempt, terminal)`，两公开方法一行委托；计数差异（beforeImport 归零 vs 存量上报）在 helper 内以 terminal 派生 |
| R1-b（§2.2） | 269821ae | 提取 `_engineForRow(row)` 共享路由核心；`reviewTargetForImport` 单次 `findByLegacyImport` 后传 row 复用，流程内 2→1；空 importId 提前返回保持原语义 |
| R2-a1（§3.1） | 0dfc1db5 | `run()` 14 处 `dao.findById(row.migrationId)!` 收敛为 `_reload(dao, row)`（单一来源化，`rollbackBeforeOwnerCommit` 独立查询不动） |
| R2-a2（§3.1） | d86dfbcc | `run()` 拆十段私有函数：`_preflight`/`_beginOrResumeRow`/`_keptLegacyReadOnly`/`_backupIfNeeded`/`_importOrReconstruct`/`_resolveOfficialSource`/`_resetAsNewIfNeeded`/`_projectIfNeeded`/`_verifyCardinalityIfNeeded`/`_publishAndSmoke` |
| R2-b（§3.2） | 821d21f1 | triage 移 `recognition/official_recognition_triage.dart`；错误映射移 `official_import_error_messages.dart`；view_helpers 只留纯格式化；`_roleLabel` 12 项 / `userFacingFieldName` 7 项展示值 / chip band 2 项迁 `AppStrings` |

### 11.2 验收实测（本机 Windows）

- `flutter analyze`：**0 issues**。
- 点名门禁（doc 39 §13 七项）：architecture guard / formal_review_launcher / projection / browser stats / scheduler_p4 / contract / diagnostics guard **全绿**（82 例）。
- 包级安全网：saga（11）+ coordinator（5）/ import_orchestrator + recovery + view_helpers（24）/ p5d routing + formal due sync + review_unification（34）全绿。
- **全量 flutter test（2,757 例）**：**1728 通过 / 29 失败**。较基线（doc 39 §15.2：2755 例 1726/29）总数 +2、通过 +2（即本批新增的 2 个 fallback 测试），失败数 29 持平；29 例逐条对照基线族零新增：media resolver 8 / golden+无障碍 10（course_tree/dictionary/round2/settings_reminder/srs 各 2）/ composition single-flight 1 / 官方导入 1 + lesson_flow 1 + backup 1 + reviewer 行为 1 + reviewer UI AV 1 + progress provider 1 + history dao 2 + review_dashboard 2（doc 39 已记录的时间窗 flaky 族）。
- 量化口径（§9）：mark* 实现 2→1（委托不计）；`reviewTargetForImport` 流程内 `findByLegacyImport` 2→1；`run()` 374 行单体→149 行扁平编排 + 10 个分段函数（单段最大 76 行，≤80 达标）；失败文案无 `${` 字面量。

### 11.3 偏差与增补（对计划正文）

1. **§3.2 错误映射未入 `recognition/`**：改置 `lib/application/anki_import/official_import_error_messages.dart`（controller 同层）——错误映射与「识别」无语义关系，塞入 recognition/ 反而误导；「view_helpers 只留纯格式化」的目的不变。
2. **§2.2 语境核实**：`findByLegacyImport` 文件内实测 3 处调用点，第三处属 `adoptExistingIfCatalogMatches`（独立方法，非 N+1 面）；本批修复面为 `reviewTargetForImport` 流程内 2→1，`engineForImport` 作为独立入口保留自身一次查询。
3. **R2-a2 行为关键注记**：`listCardsForImport` 与 resetAsNew 检查之间的 journal 重读被保留——它读取的是 `chooseSchedulingPolicy` **之后**的行状态，直接决定 resetAsNew 分支判定；拆分时一度遗漏，复核原代码时序后补回。
4. **userFacingFieldName 的 case 匹配别名**（'正面'/'背面'/'反面'）保留字面量：属输入匹配词汇（Anki 原生字段名/中文别名），非展示文案；展示返回值全部走 `AppStrings`。同值既有 getter（`ankiNotetypeSampleFront` 等）属其他语义域，不跨用，新增 `ankiFieldRole*`/`ankiFieldName*`/`ankiRecognitionBand*` 21 个。
5. **coordinator 文件 497→697 行（+200）**：分段函数签名、doc 注释与显式参数展开的固有开销；`run()` 374 行单体已消除，可读性目标达成，行数不作为本项验收指标。
6. **F1 测试加厚**：除 fallback 语义外，对全 38 个错误码枚举做无残留字面量断言，防回归面覆盖所有分支组合。

### 11.4 余项与待办门禁

- **P6/R4（§5）未施工**：Rust 四波 + 测试治理仍按 §5 表原样执行（实测锚点 as_mut 22→0、from_slice 17→~1 以施工时为准）；可与本机 Dart 包无冲突并行静态编写。
- 待办门禁（工具链主机，不变）：`cd native/turna_anki_core && PROTOC=… cargo test -p turna_anki_bridge` 全绿 + `cargo run --bin turna_anki_gen_fixtures` regen diff review（同时覆盖 doc 37/38/39/40 四批 Rust 触及面；P2 手修的 fixture RESTORE_BACKUP 应 diff 干净或仅次序）；涉 .so 波次后 `./build-android/build.sh` smoke。发布口径维持 doc 34/38 的 NO-GO 至门禁解除。
- 决策项 D1（journal 只写不消费）/ D3（每卡 5 RPC 按需化，批次三）维持 doc 39 §10 原判。

### 11.5 R4/P6 施工记录（2026-08-30，本机静态编写——波 1–3 + 测试治理落地，波 4 移交主机）

Rust 侧按铁律本机静态编写（无 cargo，全程以 vendored rslib 源码核对类型 + 括号配平 + 与金样程序化对拍兜底），独立 commit：

| 包 | commit | 摘要 |
|---|---|---|
| 波 1 | 9f58d672 | projection 死语句（连 OpenRequest import）/ STATUS_SCHEDULER_CAPABILITY_MISSING 全删；gen_fixtures BACKEND_COMMIT 改 env 注入；engine.rs STATUS/OP 常量分组升序（纯移动值不变）；projection json! 缩进订正。**engine_arc 别名统一 slot 经核实已达成（三处均 slot），无需改动** |
| 波 2 | 1bc9b727 | `parse_req`/`parse_req_or_default` 收敛 25 处 from_slice + 6 处空请求默认值；`Engine::open_col()` 收敛 31 处 `as_mut().ok_or`（ops 22/query 3/typed 2/projection 2/import 3，含 import.rs 两处全限定形态）；复制簇提取 `cid_search`/`labels_json`/`pick_state`/`answer_with_queue_fallback`/`after_mutation`（10 对 invalidate+bump 尾巴；answer_card 的 revlog 门卫块不动，属波 4） |
| 波 3 | 4f343c64 | contract.rs `OP_TABLE` 单表（35 行，严格按金样序声明，**与 response_engine_info.json 程序化比对全序一致**）驱动 name→id 与 capabilities 生成 + `capabilities_match_golden_fixture_exactly` 全集断言；errors.rs `ERROR_TABLE` 单表 (status, code, Option<message_key>) 派生双函数（29 状态/19 key 逐项等价）；**F4**：两处 `map_err(\|_\| STATUS_DECK_NOT_FOUND)` 改 `map_deck_counts_error`（rslib NotFound 仍→DECK_NOT_FOUND，其余走 map_anki_error 精确码）；ops.rs 手挑 19 能力名单测试消解为全集计数断言 |
| 测试治理 | 937a581f | 新增 `bridge/src/test_support.rs`（temp_open 带 tag+thread id / temp_open_imported / package_path 三件套 / page_all_card_ids 单一实现），ops/projection/query/import 四个测试模块改一行委托（调用点签名不变，逐名核对后增删 import）；import.rs include_str! 源码文本断言改行为断言 `create_backup_leaves_a_consistent_copy`（备份文件独立句柄 open+check_collection 全量完整性校验 + 原句柄 close/reopen 后仍 open） |

**R4 波 4 整体移交工具链主机会话**（RawValue envelope / render_card 第三次 get_card 合并 / revlog_count 单点化 / answer 域抽 ops/answer.rs）：doc 39 §8 明确 revlog_count 属热路径且「施工前先跑 host_metrics 留基线」，基线在本机（无 cargo）无法满足，故四项均按纪律顺延；`debug_details` 填充同为 wire 新增字段，随主机 minor bump 评注。perf-spike 标 `#[ignore]`（ops.rs `host_metrics_record_import_render_queue` / `import_100k_or_record_nogo` / abi `one_hundred_thousand_alloc_free_cycles`）同样必须在基线留存之后执行。

**工具链主机会话执行清单**（一次过闸覆盖 doc 37/38/39/40 四批）：

1. 基线先行：跑 `host_metrics_record_import_render_queue` 等三件 perf-spike 留基线数字，再做 perf-spike `#[ignore]` 标注与文档化显式跑法。
2. 波 4 静态稿施工（revlog_count 4→2、render_card 三读合一、envelope RawValue、ops/answer.rs 抽取），逐项对照既有测试；host_metrics 不劣化为门禁。
3. `cargo test -p turna_anki_bridge` 全绿（含本批新增 `capabilities_match_golden_fixture_exactly`、`create_backup_leaves_a_consistent_copy`）；`gen_fixtures` regen diff review 应干净或仅次序（OP_TABLE 与金样已程序化全序对拍）。
4. 涉 .so 的波次 `./build-android/build.sh` smoke → 解除 doc 34/38 的 NO-GO。

**R4 偏差注记**：①doc 39/40 曾记录「第三处 DECK_NOT_FOUND map_err 施工时确认」——实测全仓恰为 2 处（ops.rs counts_for_deck_today / ensure_today_new_quota），第三处为 `.ok_or(STATUS_DECK_NOT_FOUND)` 显式缺失判定，语义正确不动；②map_deck_counts_error 若直接改 map_anki_error 会把缺失 deck 误标 CARD_NOT_FOUND（rslib `or_not_found` 产生通用 NotFound，map_anki_error 将其映射 CARD_NOT_FOUND），故保留 NotFound→DECK_NOT_FOUND 的分流；③projection.rs fixture_root 的 canonicalize 分支实测指向不存在路径（CARGO_MANIFEST_DIR/../contract），属惰性代码，收敛时删除且行为不变。