# Anki 可维护性债务分批收口计划

> 状态：待执行  
> 编写日期：2026-08-25  
> 计划类型：Official Anki / Legacy Anki 兼容层、正式复习错误流、Review All、导入向导状态治理  
> 适用仓库：Varnamala Plus / Turna Flutter 客户端  
> 与迁移计划关系：本计划不替代 `docs/official-anki-migration/34-*`，不改变其 NO-GO、真机门禁或 W9 HOLD 口径  
> 推荐执行方式：在同一集成工作树中按 Wave 0→4 顺序完成；每一波必须保持可编译、可回归，但只有 Wave 4 总验收后才算本计划完成

---

## 0. 执行摘要

当前 Anki 设计已经建立了较清晰的核心边界：Official Collection 是卡片与调度事实源，CourseDatabase 保存可重建投影，正式评分写 Official Scheduler，Legacy 新写入受 fence 和架构守卫限制。当前主要风险不再是“没有架构”，而是迁移期留下的兼容写入口、重复策略和过重 UI/Service。

本计划只处理四组最高收益债务：

1. 把 Official formal due 从“静态兼容 facade 分字段写入”收敛为一次原子 snapshot 提交。
2. 把正式复习中的不可渲染卡从静默跳过改成结构化、可见、可恢复的产品错误闭环。
3. 删除 `official-all` 合并来源模型，只保留逐来源顺序 Review All。
4. 把 3000+ 行导入页中的流程状态和业务编排迁出 Widget，形成可测试 controller；不在本轮重写 Legacy importer 或 Official projection。

依赖顺序：

```text
Wave 0 基线与红测
  ├─ Wave 1 Due 单一写入口
  │    └─ Wave 2 不可渲染错误闭环
  ├─ Wave 3 Review All 单一模型
  └─ Wave 4 导入向导 Controller 化
          ↓
      全量回归与文档收口
```

Wave 1 必须先于 Wave 2/3 完成，因为正式复习的错误恢复、bury/suspend 和跨来源推进都需要可靠的 due snapshot。Wave 4 与前面没有数据库依赖，但应最后执行，避免在核心复习行为仍变化时同时扩大 UI diff。

---

## 1. 当前问题与证据

### 1.1 Due 名义上单一，实际上仍多入口分字段写

当前存在 `OfficialFormalDueRepository`，但生产代码大量经由 `OfficialAnkiHomeDue` 的静态 setter 写入：

- `OfficialAnkiProductionRouter` 分别写 import ids、raw due、scheduler due、placement、suspended、buried、retired、unavailable；
- `OfficialStudyLedger` 在 bury/suspend 后手工修改 map；
- Browser 在 suspend/restore 后手工修改 map；
- Play Hub 在 `build()` 中写 `turnaDue`；
- compatibility facade 的每个 setter 都调用一次 `_repo.apply()`，把一个逻辑刷新拆成多个 generation 和多次通知。

风险：

- 消费者可观察到只更新了一部分集合的中间 snapshot；
- generation 的含义从“完整同步版本”退化成“任意字段写次数”；
- 业务写入口散布在 UI、Browser、Ledger、Router，无法审计谁拥有刷新；
- `build()` 带全局副作用，容易产生重复通知和生命周期问题；
- 新代码继续依赖 facade，兼容层没有自然消亡路径。

### 1.2 不可渲染卡被吞掉，Scheduler 仍欠卡

`OfficialFormalReviewProductionLoader` 和 `OfficialFormalReviewLiveQueue` 当前在单卡 render 失败时 `catch (_) { continue; }`。这会把卡从 shared batch 移除，但不会从 Official Scheduler queue 移除、bury 或 suspend。

若当前队列全部不可渲染：

- loader 返回空 items；
- shared review page 把它当作“此来源无卡”并结束或推进下一来源；
- 用户看不到失败原因和 card id；
- 下次 session Scheduler 会再次提供同一卡；
- 现有 Reviewer ACK 测试覆盖的是另一条诊断页面错误流，未覆盖 shared formal-review loader 的静默跳过。

### 1.3 Review All 同时存在两套来源模型

目标架构 D5 是“冻结来源顺序，一次打开一个来源，来源内保持 live queue”。当前 `FormalReviewSourceCoordinator` 已实现这一路径。

但 `OfficialFormalReviewProductionLoader.load(importId: '')` 仍会：

- union 所有 source card ids；
- 使用合成 `sourceId = official-all`；
- 创建 `OfficialReviewAllPlan`；
- 把多来源卡映射成同一 synthetic source 的 `CanonicalCardKey`。

`reviewAllPlan` 目前没有产品消费者，但测试继续固化这条路径。它会模糊 bury/suspend、quota、analytics 和 card identity 的真实 sourceId，并给未来调用者提供第二种“看起来合法”的 Review All API。

### 1.4 导入页仍同时承担视图、状态机和应用编排

`AnkiImportPage` 当前超过 3300 行，包含约 50 处 `setState`，同时管理：

- 文件选择、取消和临时目录生命周期；
- Legacy parse/preview/collision/mapping/import；
- Official-first import/schema/mapping/projection/publish；
- AI 识别；
- Provider/GetIt 依赖解析；
- 导入完成后的 catalog/order/navigation；
- 全部步骤 UI。

业务 executor 已有一定拆分，但 Widget 仍是实际流程状态机。任何字段、错误或步骤变化都要同时修改若干裸字段和多个 `setState` 分支，Legacy/Official 两条路径容易漂移。

---

## 2. 目标

完成后必须达到：

1. `OfficialFormalDueRepository` 是 formal due 的唯一生产写入口。
2. 一次 refresh/mutation 只提交一个不可变 snapshot，只增加一个 generation。
3. UI build 期间不写 due 全局状态。
4. 不可渲染卡以结构化结果保留 cardId、sourceId、错误码和阶段。
5. shared formal-review 不把“全部渲染失败”冒充“没有 due card”。
6. 用户能够看到错误、重试当前来源，或明确跳过当前来源；系统不得隐式评分、bury 或 suspend。
7. Review All 只存在逐来源顺序 coordinator；不再出现 `official-all` CanonicalCardKey。
8. 每张 Official 卡始终携带真实 sourceId。
9. `AnkiImportPage` 只负责渲染和导航，不直接执行数据库/导入/projection 编排。
10. Legacy/Official 导入路径共享一套 sealed wizard state 和结构化 failure，但保留各自 writer 语义。
11. 现有 Official owner、fail-closed、projection commit-last、Legacy W9 HOLD 等约束不被削弱。

---

## 3. 非目标

本轮明确不做：

- 不删除 Legacy schema、Legacy importer、Legacy renderer 或恢复能力；物理删除仍受 W9 HOLD 控制。
- 不修改 Official Anki native/rslib 调度算法和数据库格式。
- 不重写 `OfficialAnkiSession` RPC 协议；只在错误结果需要时增加最小 DTO。
- 不拆分 `OfficialAnkiCourseProjectionService` 的全部内部职责。
- 不引入多 profile 产品功能；只消除本轮触及代码中的新增硬编码。
- 不重做导入页视觉设计、文案品牌或 mapping 算法。
- 不更换 Provider/GetIt 全局 DI 方案；controller 只通过构造参数接收当前所需依赖。
- 不把本计划写成“Official Anki 迁移完成”收据。

---

## 4. 不可破坏约束

### 4.1 所有权约束

- Official owner 的评分、undo、redo、bury、suspend 只能写 Official engine。
- Legacy owner 的正式复习不能误写 Official scheduler。
- projection、due repository 和 UI 不得成为第三个 scheduler writer。
- 不可渲染错误不能通过自动 bury/suspend“修复”。

### 4.2 身份约束

- `CanonicalCardKey.sourceId` 必须是真实 import/source id，禁止 `official-all` 等合成 owner。
- Review All 可以聚合结果，但不能聚合身份。
- sourceId、cardId、profileId 必须在 loader、presentation、ledger receipt 和 analytics 中 round-trip。

### 4.3 状态约束

- due snapshot 中六集合必须同一代提交：scheduler due、active placement、introduced、suspended、buried、retired。
- refresh 失败保留上一份完整可用 snapshot，并标记 unavailable；不得落地半份新结果。
- stale generation 不覆盖较新完整结果。
- 不可渲染卡不是“已完成”、不是“无 due”、也不是“评分失败”。

### 4.4 UI/生命周期约束

- Widget `build()` 不修改 repository、prefs、数据库或 engine。
- controller 的异步结果必须通过 operation token/generation 丢弃过期回调。
- 页面 dispose 后不更新状态、不泄漏临时文件、不继续导入进度通知。
- 导入取消必须保留现有的 cleanup/rollback 语义。

---

## 5. 目标架构

### 5.1 Due 写模型

```text
Official Scheduler + Course placement + Introduction store
                  ↓ collect
          OfficialFormalDueSnapshotBuilder
                  ↓ one commit
          OfficialFormalDueRepository
                  ↓ read-only snapshot
      Home / Hub / Profile / Review / Stats
```

建议新增不可变写模型：

```dart
@immutable
class OfficialFormalDueUpdate {
  const OfficialFormalDueUpdate({
    required this.bySource,
    required this.rawDueBySource,
    required this.turnaDue,
    required this.unintroducedNew,
    this.unavailable = false,
    this.error,
  });

  final Map<String, OfficialFormalDuePerSource> bySource;
  final Map<String, int> rawDueBySource;
  final int turnaDue;
  final int unintroducedNew;
  final bool unavailable;
  final Object? error;
}
```

Repository 只暴露：

```dart
OfficialFormalDueSnapshot get snapshot;
void commit(OfficialFormalDueUpdate update, {required int basedOnGeneration});
void markUnavailable(Object error);
void resetForTest();
```

`commit` 必须执行 generation CAS：若 `basedOnGeneration != current.generation`，返回 `stale` 而不是覆盖。

mutation 更新不再改某个静态 map，统一为：

```dart
repo.mutateSource(
  sourceId,
  expectedGeneration: generation,
  transform: (source) => source.copyWith(...),
);
```

它仍是一次完整 snapshot 提交。

`introduced` 不能继续在 getter 中临时查询后绕过 snapshot。`CardIntroductionStore` 仍负责持久化 introduction ledger，但每次 introduction/retire mutation 成功后必须发布带真实 sourceId 的变更事件，由 due repository 在同一 source 上执行 CAS mutation；若事件提交发现 generation stale，则触发 source-scoped refresh。这样既保持学习过程中 introduction 立即生效，又保证消费者读到的是完整、不可变、同一代的六集合。

### 5.2 Formal review 加载结果

loader 不再只用 `batch/null/empty` 表达所有状态：

```dart
sealed class OfficialFormalReviewLoadResult {
  const OfficialFormalReviewLoadResult();
}

final class OfficialFormalReviewReady
    extends OfficialFormalReviewLoadResult {
  const OfficialFormalReviewReady(this.batch);
  final OfficialFormalReviewBatch batch;
}

final class OfficialFormalReviewNoDue
    extends OfficialFormalReviewLoadResult {
  const OfficialFormalReviewNoDue();
}

final class OfficialFormalReviewBlocked
    extends OfficialFormalReviewLoadResult {
  const OfficialFormalReviewBlocked({
    required this.sourceId,
    required this.failures,
    required this.schedulerCardCount,
  });

  final String sourceId;
  final List<OfficialCardRenderFailure> failures;
  final int schedulerCardCount;
}
```

```dart
@immutable
class OfficialCardRenderFailure {
  const OfficialCardRenderFailure({
    required this.sourceId,
    required this.cardId,
    required this.code,
    required this.stage,
    this.debugDetails,
  });

  final String sourceId;
  final int cardId;
  final String code;
  final OfficialRenderFailureStage stage;
  final String? debugDetails;
}
```

判定规则：

- scheduler queue 空：`NoDue`；
- queue 非空且至少一张成功：`Ready`，同时 batch 携带非阻断 failures 供 session summary 展示；
- queue 非空且零张成功：`Blocked`；
- engine/session 失败：抛/映射现有 `OfficialAnkiException`，不得伪装成 `NoDue`。

### 5.3 Review All

```text
FormalReviewSourceCoordinator
  source A -> owner-specific live session -> record result
  source B -> owner-specific live session -> record result
  source C -> load failure -> record failure -> explicit continue
  completion -> aggregate counts + failure summary
```

规则：

- coordinator 在启动时冻结真实 source 列表和顺序；
- 每次 loader 只接收非空真实 sourceId；
- loader 删除 `importId.isEmpty` 的 union 分支；
- `OfficialReviewAllPlan` 删除；
- `OfficialFormalReviewBatch.reviewAllPlan` 删除；
- fallback 也必须先构造真实 `FormalReviewSourceTarget`，不能调用 synthetic aggregate loader。

### 5.4 导入向导

```text
AnkiImportPage
  ↓ intent
AnkiImportController
  ├─ LegacyAnkiImportFlow
  └─ OfficialFirstAnkiImportFlow
          ↓
  existing executors/services
```

建议状态：

```dart
sealed class AnkiImportWizardState {
  const AnkiImportWizardState();
}

final class AnkiImportSelecting extends AnkiImportWizardState { ... }
final class AnkiImportParsing extends AnkiImportWizardState { ... }
final class AnkiImportPreviewing extends AnkiImportWizardState { ... }
final class AnkiImportCommitting extends AnkiImportWizardState { ... }
final class AnkiImportCompleted extends AnkiImportWizardState { ... }
final class AnkiImportFailed extends AnkiImportWizardState { ... }
```

Preview payload 使用显式 variant：

```dart
sealed class AnkiImportPreviewModel { ... }
final class LegacyAnkiImportPreviewModel extends AnkiImportPreviewModel { ... }
final class OfficialAnkiImportPreviewModel extends AnkiImportPreviewModel { ... }
```

Widget 不再通过 `_officialSourceId != null` 推断当前 flow。

---

## 6. Wave 0：基线冻结与红测

### 6.1 基线记录

执行前记录：

- `git status --short`
- 主工程 revision 和 native submodule revision/status
- `flutter analyze`
- 全量非 Golden 测试基线
- Anki 定向测试基线
- 当前 release APK 构建结果仍引用 34 收据，不在本计划伪造设备结果

### 6.2 必须先写的失败测试

新增或扩展以下测试，且在生产实现前应能证明当前行为不满足目标：

1. `test/application/anki_official/official_formal_due_atomic_update_test.dart`
   - 一次 formal due refresh 只增加一个 generation；
   - listener 只收到一个完整 snapshot；
   - 不存在只更新 schedulerDue、尚未更新 placement 的中间通知；
   - stale commit 被拒绝；
   - mutation 与 refresh 竞争时不会丢 suspended/buried。
   - introduction/retire mutation 立即生成新完整 snapshot，不依赖 getter 动态旁路；
2. `test/application/anki_official/official_formal_review_unrenderable_test.dart`
   - queue 非空、全部 render 失败返回 Blocked；
   - 部分失败返回 Ready + failures；
   - 不调用 answer/bury/suspend；
   - retry 后成功能够进入同一 source session；
   - live rebuild 新出现的不可渲染 current 不被静默吞掉。
3. 扩展 `official_review_all_coordinator_test.dart`
   - 每个 source 单独调用 loader；
   - 每张 cardKey 保留真实 sourceId；
   - 禁止字符串 `official-all`；
   - 一个来源 Blocked 时记录 failure，并按用户动作继续/重试；
   - completion 汇总多个真实来源。
4. `test/views/anki/anki_import_controller_test.dart`
   - pick-time plan 在整个流程保持冻结；
   - Legacy/Official preview 由 variant 表达；
   - 过期异步回调不覆盖新选择；
   - dispose/cancel 清理临时目录；
   - commit 中重复点击只触发一次 executor；
   - Official-first 失败产生零 Legacy 写。

### 6.3 Wave 0 完成定义

- [ ] 新测试准确描述目标行为，不依赖生产源码字符串拼接；
- [ ] 至少 due 原子性、unrenderable、synthetic source 三项在旧实现上失败；
- [ ] 记录现有全量基线；
- [ ] 不修改数据库 schema；
- [ ] 不改变任何产品入口。

---

## 7. Wave 1：Due repository 单一写入口

### 7.1 新增完整 snapshot builder

建议文件：

- `lib/application/anki_official/engine/official_formal_due_update.dart`
- `lib/application/anki_official/engine/official_formal_due_snapshot_builder.dart`

builder 输入必须显式包含所有六集合和同步知识状态。不得让缺失参数默认为“已知空集合”；需要区分：

- `known empty`
- `unknown / not fetched`
- `previous value preserved`（只允许 mutation helper 使用）

### 7.2 改造 Repository

修改：

- `official_formal_due_repository.dart`

要求：

- `apply` 重命名/收敛为一次完整 `commit`；
- commit 接受 expected generation；
- `markUnavailable` 保留最后完整 snapshot；
- rollback 不再依赖可被覆盖的单个 `_rollbackSnapshot`，优先使用“先构建、后 commit”，异常前不改变 repository；
- 所有 map/set 在 snapshot 边界复制为不可变集合，外部引用不能原地修改；
- `isStale` 必须由生产 refresh 使用，不能只存在于测试。

### 7.3 改造刷新链路

修改：

- `official_anki_home_due_sync.dart`
- `official_anki_production_router.dart`

目标：Router 从“写全局状态”改为“返回数据”。例如：

```dart
Future<OfficialFormalDueUpdate> collectFormalDue(...)
```

`OfficialAnkiHomeDueSync`：

1. 读取 `baseGeneration`；
2. 完成 catalog、deck tree、queue、suspended/buried/retired 和 placement 收集；
3. 构造一个 update；
4. 一次 commit；
5. 若 generation 已变化，重新收集或返回 stale，不覆盖新状态。

Router 中禁止继续引用 `OfficialAnkiHomeDue.* =`。

### 7.4 改造 mutation 更新

修改：

- `study_ledger_adapters.dart`
- `official_anki_source_aware_browser.dart`
- `card_introduction_store.dart`

bury/suspend/restore 成功后：

- 优先触发 source-scoped refresh；
- 若需要乐观更新，使用 repository 的 CAS `mutateSource`；
- 乐观更新失败或 refresh 失败时保留旧完整 snapshot并标记 stale/unavailable；
- 不手工 spread 静态 map。

Introduction/retire 更新要求：

- `CardIntroductionStore` 的数据库写成功后发布 `CardIntroductionChanged(sourceId, cardId, introduced/retired)`；
- due repository 订阅者只复制并替换对应 source 的 introduced/retired set；
- 事件必须发生在持久化成功之后，失败写入不得乐观标记为已 introduced；
- App 冷启动仍由完整 due sync 从 ledger 重建 introduced set；
- 删除 `OfficialFormalDuePerSource.formalDueCardKeys` 中每次 getter 调用 `CardIntroductionStore.resolve()` 的动态旁路；
- introduction 事件与后台 refresh 竞争时使用 generation CAS，失败的一方重试 source refresh，不以 last-write-wins 覆盖。

### 7.5 删除 build 副作用

修改：

- `views/play/play_hub_screen.dart`

`turnaDue` 不再写入 Official repository。聚合值在 selector/view model 中即时计算：

```dart
final ankiDue = legacyDue + officialSnapshot.introducedOfficialDue;
```

如果确实需要跨页面保存 Turna due，应由 SrsProvider 自己持有，而不是混进 Official snapshot。

### 7.6 兼容 facade 退役

修改：

- `official_anki_home_due.dart`

分两步：

1. 先删全部 setter，仅保留只读 forwarding getters，并在注释中列出删除期限；
2. 迁移所有消费者后删除 facade，直接注入/读取 `OfficialFormalDueRepository`。

新增 architecture guard：

- 禁止生产代码出现 `OfficialAnkiHomeDue.<field> =`；
- 禁止 Widget `build` 调用 repository mutation；
- 新文件不得 import compatibility facade。

### 7.7 Wave 1 完成定义

- [ ] 一次完整 refresh 只 commit 一次；
- [ ] Router 无全局 due 写入；
- [ ] Browser/Ledger 无静态 map spread 写；
- [ ] introduction/retire 持久化成功后立即更新对应 source snapshot；
- [ ] formalDue getter 不再动态读取 IntroductionStore 绕过 snapshot；
- [ ] Play Hub build 无副作用；
- [ ] 所有集合不可从 snapshot 外部修改；
- [ ] stale commit 在生产代码被处理；
- [ ] 旧 facade 无 setter，最好已删除；
- [ ] Home/Hub/Profile/Review/Stats 读取同一代 snapshot；
- [ ] 定向测试与 analyze 全绿。

---

## 8. Wave 2：不可渲染卡错误闭环

### 8.1 Renderer 返回结构化失败

修改：

- `official_formal_review_coordinator.dart`
- `official_formal_review_production_loader.dart`
- 需要时扩展 `official_anki_errors.dart`

不得保留裸 `catch (_) { continue; }`。将 `OfficialAnkiException` 映射为稳定 code；未知异常映射为 `render_internal_error`，debug 信息只在 debug/日志中使用。

需要记录：

- sourceId
- cardId
- question/answer/load/rebuild 阶段
- recoverable/fatal
- messageKey/code
- 当前 queue epoch 或 render generation

### 8.2 Loader 判定 Ready/NoDue/Blocked

修改 `OfficialFormalReviewProductionLoader.load` 返回类型。

要求：

- queue 空才是 NoDue；
- queue 非空但 items 空必须是 Blocked；
- 部分成功的 batch 保留 failure list；
- batch 只允许包含成功 render 且仍在当前 queue 的卡；
- current card render 失败时不得让 controller 指向另一个卡并继续评分。

### 8.3 Live queue 重建错误

`OfficialFormalReviewLiveQueue.rebuildFromLiveQueue` 改为返回：

```dart
sealed class OfficialLiveQueueRebuildResult { ... }
```

至少区分：

- rebuilt
- blockedOnCurrentCard
- stale
- failed

若 current card 不可渲染：

- 保留上一份 UI snapshot但锁定评分；
- 暴露错误给页面；
- 不清空 items 后假装完成；
- 用户重试时重新 render 同一卡和当前 generation。

### 8.4 Shared review page 产品交互

修改：

- `views/anki/anki_review_session_page.dart`

增加统一错误面：

- “此卡暂时无法显示”；
- 重试当前来源；
- Review All 中允许“稍后处理此来源并继续”，但必须在完成页列为失败来源；
- 单来源复习不可静默结束；
- debug 模式显示 cardId/sourceId/code，release 只显示安全文案；
- 不提供会暗中更改 Scheduler 的“跳过卡片”按钮。

### 8.5 观测与审计

复用/扩展 audit log：

- `formal_review_render_failure`
- sourceId/cardId/code/stage/recoverable
- 不记录卡片正文、HTML、typed answer 或媒体路径

### 8.6 Wave 2 完成定义

- [ ] shared loader 无吞异常 continue；
- [ ] queue 非空且零成功时显示 Blocked；
- [ ] current render 失败时评分按钮禁用；
- [ ] retry 不创建第二个 scheduler session、不重复评分；
- [ ] Review All failure 被汇总；
- [ ] 不可渲染行为不调用 bury/suspend/answer；
- [ ] failure telemetry 不包含卡片内容；
- [ ] 对应 widget/unit 测试全绿。

---

## 9. Wave 3：Review All 单一来源模型

### 9.1 锁定唯一策略

唯一生产策略：`FormalReviewSourceCoordinator` 顺序消费真实来源。

删除：

- `OfficialReviewAllPlan`
- `OfficialFormalReviewBatch.reviewAllPlan`
- `_resolveAnyProductionTarget`
- `_planReviewAll`
- `sourceId = 'official-all'`
- loader 的 `importId.isEmpty` aggregate 分支
- “empty importId loads aggregate multi-source batch”测试

### 9.2 Loader 契约收紧

`OfficialFormalReviewProductionLoader.load`：

- `sourceId/importId` 必填且非空；
- 只 resolve 一个真实 target；
- allowed card ids 只属于该 target；
- introduction/placement/suspended/buried/retired 只读该 source snapshot；
- 不 union 多来源集合；
- 结果中的所有 CanonicalCardKey.sourceId 等于 target.sourceId。

### 9.3 Coordinator fallback

修改：

- `formal_review_source_coordinator.dart`
- `anki_review_session_page.dart`

fallback 顺序：

1. Course catalog 的非 builtin entry；
2. Due repository snapshot 中的真实 source ids；
3. 两者都无来源则显示 NoDue/Unavailable，绝不传空 source 给 loader。

启动时冻结 `List<FormalReviewSourceTarget>`，中途 due refresh 不改变本 session 来源顺序。

### 9.4 Failure 与完成汇总

`FormalReviewSourceFailure` 扩展：

- source target
- failure kind（load/render/runtime）
- retryable
- stable code

完成页显示：

- 完成来源数；
- 记住/忘记/总数；
- 未完成来源及重试入口；
- 不把失败来源计入完成数量。

### 9.5 Architecture guard

新增守卫：

- `lib/` 中禁止字符串 `official-all`；
- production loader 禁止接受空 sourceId；
- Review All 只允许从 coordinator 启动；
- Official card key sourceId 必须来自 routed target。

### 9.6 Wave 3 完成定义

- [ ] 生产代码不存在 `official-all`；
- [ ] `OfficialReviewAllPlan` 完全删除；
- [ ] 每个来源独立 live scheduler session；
- [ ] mixed Legacy + Official 按冻结顺序推进；
- [ ] 每张卡保留真实 sourceId；
- [ ] 一个来源失败不污染其他来源 ledger；
- [ ] 完成页列出失败来源；
- [ ] 旧 aggregate 测试删除并由真实来源测试替换。

---

## 10. Wave 4：导入向导 Controller 化

### 10.1 第一阶段：只搬状态，不改行为

新增建议文件：

- `lib/application/anki/import_wizard/anki_import_controller.dart`
- `lib/application/anki/import_wizard/anki_import_wizard_state.dart`
- `lib/application/anki/import_wizard/anki_import_dependencies.dart`
- `lib/application/anki/import_wizard/legacy_anki_import_flow.dart`
- `lib/application/anki/import_wizard/official_first_anki_import_flow.dart`

Controller 使用 `ChangeNotifier` 或项目既有可观察模式；不在本轮引入新的状态管理框架。

构造参数显式注入：

- file picker abstraction
- execution planner/facade
- Legacy importer/executor factory
- Official-first service
- recognition pipeline factory
- CourseDatabase / CourseProvider gateway
- settings snapshot
- clock/logger（若确有需要）

Widget 不再直接 `getIt<T>()` 拼装业务依赖。

### 10.2 Intent API

Controller 至少提供：

```dart
Future<void> pickFile();
Future<void> proceedWithPath(String path);
Future<void> loadSample();
Future<void> editLegacyMapping(...);
Future<void> identifyWithAi();
Future<void> confirmOfficialMapping(...);
Future<void> skipOfficialNotetype(...);
Future<void> commit();
void cancel();
void reset();
Future<void> disposeAsync();
```

同一时间只允许一个长操作。每次新 pick/reset 增加 operation generation；旧 parse/AI/projection 回调必须发现 token stale 并丢弃。

### 10.3 State 不变量

- Selecting：没有活动 collection/service/temp dir；
- Parsing：有冻结 plan 和 path；
- Previewing：只持有一种 preview variant；
- Committing：重复 commit intent no-op；
- Completed：包含统一 summary，不再由 Widget临时拼装；
- Failed：包含 return state，能回到 select 或 preview；
- Official preview 不允许出现 Legacy collision strategy；
- Legacy preview 不允许持有 Official projection service。

使用 constructor/assert 或 sealed type 保证无效组合无法构造，不再靠 nullable 字段组合表达状态。

### 10.4 Flow 职责

`LegacyAnkiImportFlow`：

- parse/sample；
- recognition + organization preview；
- collision inspection；
- 调用 `LegacyAnkiImportExecutor`；
- 返回统一 summary；
- 不直接导航。

`OfficialFirstAnkiImportFlow`：

- 调用 `OfficialAnkiOfficialFirstService.importThenPreview`；
- 管理 schema suggestion/confirm/skip；
- 调用 projectAndPublish；
- 返回统一 summary；
- 不访问 Legacy NoteStore/SRS writer。

### 10.5 页面拆分

`AnkiImportPage` 保留：

- Scaffold/AppBar/stepper；
- 监听 controller state；
- 按 variant 渲染 step；
- mapping route/dialog；
- done 后的导航动作。

建议拆出纯 Widget：

- `anki_import_select_step.dart`
- `anki_import_progress_step.dart`
- `legacy_anki_import_preview.dart`
- `official_anki_import_preview.dart`
- `anki_import_done_step.dart`
- `anki_notetype_mapping_editor.dart`

这些 Widget 只接收 model + callbacks，不 import database、engine、DAO、GetIt。

### 10.6 Cleanup 与导航

- 临时 media dir 所有权由 flow/controller 管理；
- dispose/cancel/失败只清理由当前 operation 创建的目录；
- 完成后 controller 释放 collection 大对象；
- course reload/order persistence 进入一个 `AnkiImportCompletionCoordinator`，Legacy/Official 共用；
- “完成”不切 active course，“立即学习”才切换的现有语义保持不变；
- Widget 只根据 completed summary 执行 route intent。

### 10.7 迁移策略

禁止一次重写整个页面。按以下机械顺序：

1. 为现有裸字段建立 state DTO，Widget 暂时仍写 DTO；
2. 引入 controller，先搬 select/parse/cancel；
3. 搬 Legacy preview/commit；
4. 搬 Official preview/commit；
5. 搬 AI recognition；
6. 搬 completion reload/order；
7. 拆纯 Widget；
8. 删除旧字段、旧 helper 和重复 error mapping。

每一步都必须保持既有 widget 测试通过，不允许同时改视觉和流程。

### 10.8 代码规模门禁

完成后建议门禁：

- `anki_import_screen.dart` ≤ 700 行；
- 单个 step Widget ≤ 500 行；
- controller 建议 ≤ 600 行，Legacy/Official flow 各 ≤ 500 行；
- 页面不 import DAO、CourseDatabase、engine implementation；
- 页面不出现 `getIt<`；
- 页面不直接调用 importer/projection service；
- `setState` 仅用于局部 UI（如 disclosure/animation），业务步骤由 controller state 驱动。

行数不是最终设计目标，但可防止把同一巨石换个文件名继续存在。

### 10.9 Wave 4 完成定义

- [ ] sealed wizard state 覆盖全部步骤；
- [ ] Legacy/Official flow 不能同时 active；
- [ ] pick-time plan 全程冻结；
- [ ] 重复 commit 不产生第二次写入；
- [ ] stale async callback 不覆盖新 state；
- [ ] 临时目录在 cancel/dispose/failure 后回收；
- [ ] 页面无业务 GetIt/DAO/engine 依赖；
- [ ] 完成导航语义不变；
- [ ] `anki_import_screen.dart` 达到规模门禁；
- [ ] 原 widget/golden 视觉无非预期变化。

---

## 11. 逐文件施工地图

| 文件/目录 | 动作 | 目标 |
| --- | --- | --- |
| `official_formal_due_repository.dart` | 重构 | 原子 commit、CAS generation、不可变集合 |
| `official_formal_due_update.dart` | 新增 | 完整 due 写模型 |
| `official_formal_due_snapshot_builder.dart` | 新增 | 六集合收集与校验 |
| `official_anki_home_due.dart` | 删除或只读过渡 | 移除全部生产 setter |
| `official_anki_home_due_sync.dart` | 重构 | collect-then-commit，一次提交 |
| `official_anki_production_router.dart` | 重构 | 返回数据，不写全局状态 |
| `study_ledger_adapters.dart` | 修改 | mutation 后 source refresh/CAS |
| `official_anki_source_aware_browser.dart` | 修改 | suspend/restore 后统一刷新 |
| `card_introduction_store.dart` | 修改 | 持久化后发布 source-scoped introduction/retire 事件 |
| `play_hub_screen.dart` | 修改 | 删除 build 写状态 |
| `official_formal_review_production_loader.dart` | 重构 | typed load result，单真实 source |
| `official_formal_review_coordinator.dart` | 重构 | typed render/rebuild failure；删除 ReviewAllPlan |
| `formal_review_launcher.dart` | 修改 | batch 携带 failures；删除 reviewAllPlan |
| `formal_review_source_coordinator.dart` | 扩展 | 唯一 Review All owner、failure summary |
| `anki_review_session_page.dart` | 修改 | Blocked UI、retry/continue、真实来源推进 |
| `anki_import_screen.dart` | 缩减 | 仅保留页面 shell 和导航 |
| `application/anki/import_wizard/` | 新增 | controller、state、两条 flow、依赖接口 |
| `views/anki/import_wizard/` | 新增 | 纯 step Widget 与 mapping editor |
| architecture guard tests | 扩展 | 禁静态 due 写、禁 official-all、禁页面业务依赖 |

---

## 12. 测试矩阵

### 12.1 Due

- 六集合公式与 unknown/fail-closed；
- 单来源、多来源隔离；
- 一次 refresh 一次通知/一次 generation；
- refresh 与 bury/suspend 并发；
- refresh 与 introduction/retire 并发；
- stale refresh 丢弃；
- refresh 失败保留完整旧 snapshot；
- Home/Hub/Profile/Review/Stats 同代读取；
- snapshot 外部不可变。

### 12.2 Formal review

- rich/plain/MathJax/typed answer fidelity；
- current render 全失败、部分失败、重试成功；
- live queue answer 后新增不可渲染 current；
- failure 不评分、不 bury、不 suspend；
- retry 保持 cardId/queue epoch 一致；
- source A 失败不影响 source B；
- failure summary 不泄露内容。

### 12.3 Review All

- 两个 Official 来源顺序执行；
- Legacy + Official 混合执行；
- 每张 key 使用真实 sourceId；
- source list 启动后冻结；
- 空 catalog + due snapshot fallback；
- 一个来源 NoDue 自动推进；
- 一个来源 Blocked 等待用户选择；
- 汇总统计和失败来源准确；
- lib 中不存在 `official-all`。

### 12.4 Import wizard

- file picker cancel/invalid extension；
- Legacy parse/preview/AI mapping/commit/cancel；
- Official-first preview/mapping/skip/project/publish；
- flag-off fail closed 零写入；
- same/replace/append 策略保持；
- repeated commit single-flight；
- abandon preview cleanup；
- stale callback；
- completion course order；
- “完成”不切课，“立即学习”切课；
- sample 保持 Legacy haemostasis 语义；
- 200% text scale/narrow screen 视觉回归。

### 12.5 必跑命令

```bash
flutter analyze

flutter test \
  test/application/anki/anki_unification_architecture_guard_test.dart \
  test/application/anki_official/official_formal_due_repository_test.dart \
  test/application/anki_official/official_formal_due_atomic_update_test.dart \
  test/application/anki_official/official_formal_review_unrenderable_test.dart \
  test/application/anki_official/official_live_formal_review_test.dart \
  test/application/anki_official/official_review_all_coordinator_test.dart \
  test/application/anki_official/official_formal_review_fidelity_test.dart \
  test/views/anki/anki_import_screen_test.dart \
  test/views/anki/anki_import_official_first_test.dart \
  --reporter compact

flutter test --exclude-tags golden --reporter compact
flutter test --tags golden --reporter compact
git diff --check
```

若本计划合入 34 的 release candidate，还必须重跑 34 指定的 native、arm64 APK 和真机矩阵；本计划的 host 测试不能替代设备证据。

---

## 13. 性能与资源门禁

- due refresh 不得因多次 setter 产生重复全页 rebuild；一次刷新最多一次 repository notify；
- Review All 同一时刻只保留一个来源 session 和必要 render cache；
- 不可渲染 failure 不缓存完整 HTML；
- 导入 controller 完成/取消后释放 `AnkiCollection`、schema samples 和临时 media dir；
- 5K 卡导入不得因 immutable state 每次复制完整 cards/notes；state 保存引用/摘要，重对象由 flow owner 持有；
- UI state 更新不在 build 中执行 O(cards) 扫描；
- 本轮不得让 cold-start 为显示 due 同时打开第二个 Official writer。

建议基线采样：

- Play Hub due refresh 通知次数；
- 100/5K 卡 import preview 和 commit 时间；
- Review All 来源切换耗时；
- render failure retry 耗时；
- session 结束前后 Dart heap/RSS 趋势（只做诊断，不作为精确内存承诺）。

---

## 14. 回滚与失败处理

### 14.1 Wave 1

无数据库 schema 变化。若原子 repository 施工失败：

- 回滚生产消费者到旧 facade；
- 不保留一半消费者写新 repo、一半写旧 setter 的状态；
- architecture guard 只有在所有写入口迁移完后才转为硬失败。

### 14.2 Wave 2

typed load result 必须与页面同一 checkpoint 合入。不能只改 loader 返回 Blocked、页面仍按 null/empty 处理。

若 UI 未完成：恢复旧 loader API和调用方；不得保留 silent catch 与半接线 error DTO。

### 14.3 Wave 3

删除 synthetic Review All 前必须确认所有入口先经过 coordinator。若发现直接空 source 调用者，先迁移调用者，不能保留 fallback 到 `official-all`。

### 14.4 Wave 4

每次只迁移一个 intent group；保留 checkpoint。若 controller 化无法在窗口内完成，回退到上一个“该流程全部仍由 Widget 或全部已由 controller owner”的一致点，禁止双 owner。

### 14.5 用户数据

本计划不执行 Legacy 清理、不改 collection schema、不批量迁移用户卡片。任何测试必须使用内存库、fixture 或明确的临时 profile，不对真实用户库做演练。

---

## 15. 建议 checkpoint

以下 checkpoint 只用于内部回滚，不代表可发布阶段：

1. `test(anki): lock due/render/review-all debt regressions`
2. `refactor(anki): commit formal due as atomic snapshots`
3. `fix(anki): surface unrenderable formal review cards`
4. `refactor(anki): keep one sequential review-all model`
5. `refactor(anki): move import flow into controller`
6. `test(anki): close maintainability cleanup matrix`

每个 checkpoint：

- analyze 通过；
- 对应定向测试通过；
- `git diff --check` 通过；
- 不包含无关工作树修改。

---

## 16. 总体 Definition of Done

只有全部满足才可标记本计划完成：

- [ ] Due 只有一个生产写入口，一次逻辑更新一次 commit；
- [ ] 所有 Due 消费者读取同一 repository snapshot；
- [ ] Widget build 无 Due 写副作用；
- [ ] 不可渲染卡有结构化、可见、可重试错误；
- [ ] Scheduler queue 非空不会被误报为 NoDue；
- [ ] render failure 不触发任何隐式调度写；
- [ ] Review All 只使用顺序真实来源模型；
- [ ] `official-all` 和 `OfficialReviewAllPlan` 已删除；
- [ ] 所有 Official CanonicalCardKey 保留真实 sourceId；
- [ ] 导入页业务流程由 controller + flow owner；
- [ ] 页面不直接访问 DAO/engine/importer/projection；
- [ ] Legacy/Official preview 使用 sealed variant；
- [ ] cancel/dispose/stale callback/repeated commit 均有回归测试；
- [ ] architecture guards 防止旧模式回流；
- [ ] `flutter analyze` 0 issue；
- [ ] 定向、全量非 Golden、Golden 全绿；
- [ ] `git diff --check` 通过；
- [ ] 若进入 release candidate，34 的 native/APK/真机门禁重新执行；
- [ ] 文档准确写“可维护性债务收口完成”，不写“Official Anki 迁移完成”；
- [ ] W9 Legacy 物理删除继续 HOLD，除非另有满足门禁的独立批准。

---

## 17. 明确留到后续的债务

本计划完成后仍会存在、但不应顺手扩张的项目：

1. `OfficialAnkiSession` 客户端/worker/dispatcher 的 typed RPC 拆分。
2. `OfficialAnkiCourseProjectionService` 的 mapping DAO、job runner、reader、publisher 拆分。
3. `OfficialAnkiCompositionRoot` 静态生命周期、catalog close/reset 和 profile context 注入。
4. `profile-default-01` 全仓集中化与真正多 profile 支持。
5. `official_anki_internal_page.dart` 从 application 目录迁到 diagnostics/views，并删除架构守卫 allowlist。
6. W9 Legacy importer/scheduler/schema 物理删除。

这些项目应分别立项。尤其 W9 不能因为本计划把兼容调用减少，就绕过观察期、备份恢复和真实用户数据门禁。
