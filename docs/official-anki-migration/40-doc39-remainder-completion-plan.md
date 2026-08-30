# 40 — doc 39 收尾施工计划（P5 余量 / F1 转义 bug / Rust 收敛四波）

> 状态：**已登记待施工（2026-08-30）**。doc 39 的 P1 全簇、P2、P3、P4、F2、F3 及 P5 前半已施工并独立 commit（清单见 §1）；本计划把剩余未完成项整理为 R1–R4 + P6 五个独立施工包，口径与 doc 39 一致：**不改功能效果**的清理照旧，F1 是用户可见 bugfix 单列。
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

## 11. 施工记录（待填）

> 每包施工后按 doc 38 §12 格式补：commit 清单、验收实测（含基线对照）、偏差与增补、待办门禁。