# Phase 4 验货、修补与 Phase 5 Legacy 迁移实施计划

> 文档代号：P4-AUDIT / P5-EXECUTION  
> 日期：2026-08-17  
> 仓库：`Varnamalaplus`  
> 审查基线：`81ba44b3bf11fc91846f787346245a17fd96a897` + 当前 dirty worktree  
> 官方 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 审查范围：License 除外；P4 Scheduler 实现、测试、Android 证据、生产接线，以及 P5 Legacy 迁移与删除  
> 前置文档：`12-phase-4-official-scheduler-implementation-plan.md`、`13-phase-4-result-report.md`  
> 设备结论更新：Formal Reviewer 与 Device A 最新证据以 `16-p4r3-production-gate-and-p5b-prep-plan.md` 及后续结果报告为准；P4 生产默认与 P5 Cutover 仍为 NO-GO。

## 1. 结论先行

本次验货结论不是“P4 已完成，可以直接删除 Legacy”，而是：

```text
P4 HOST / NATIVE CONTRACT：CONDITIONAL GO
P4 FORMAL REVIEW INTEGRATION：已被 Device A artifact / 18 取代（生产默认仍 NO-GO）
P4 TECHNICAL ACCEPTANCE：NO-GO
P4 PRODUCTION：NO-GO

P5 READ-ONLY INVENTORY / SCHEMA PREPARATION：GO
P5 USER DATA MIGRATION / CUTOVER：NO-GO（被 P4 阻断）
P5 LEGACY PHYSICAL DELETION：NO-GO
```

P4 的官方 Scheduler bridge、opaque answer token、四档评分、Undo/Redo、Bury/Suspend 等 Host 基础已经存在，159 个 Flutter official 测试也通过。但是“正式复习页”和“官方 Reviewer”仍是两个互不联动的状态机：外层点击 `Show Answer` 后会开放评分按钮，却没有让内层官方卡片翻到答案面。现有 widget test 又用 `SizedBox` 替代真实 Reviewer，因此只验证了按钮显隐，没有验证“官方答案已成功呈现后才允许评分”。这是生产评分的 P0 阻断。

此外，Android 证据链存在三个不同的 native hash，设备截图明确显示双层 AppBar 和两个“显示答案”按钮，首次渲染还有 `RENDER_TIMEOUT`。因此当前 1 卡 debug smoke 只能证明“部分操作可调用”，不能证明正式复习闭环正确。

P5 本身尚未开始阶段性实现：没有 `engineKind`、`migrationState`、`migratedSourceId`，没有 Legacy migration registry、card map、迁移用例或正式路由切换。现有 30 个 Legacy Dart 文件约 14,995 行，至少 10 个目录外生产文件仍直接依赖 Legacy；正常 Anki 复习继续写 Turna `SrsProvider`，正式官方复习仅能从内部调试页进入。P5 可以现在开始只读盘点、schema 和迁移模拟器，但在 P4 修补通过前不得切流量、冻结用户数据或删除 Legacy。

## 2. 验货方法和现场事实

本次没有直接采信结果报告中的勾选，而是同时核对了源码、测试、APK 内容、设备截图和 artifacts。

### 2.1 实际执行结果

| 检查 | 本次结果 | 判定 |
|---|---|---|
| `flutter test --no-pub test/application/anki_official` | 159 passed | PASS，但覆盖缺口见第 4 节 |
| `flutter analyze --no-pub lib/application/anki_official lib/views/anki_official test/application/anki_official` | No issues found | PASS |
| Rust `cargo test --lib`，默认并行 | 63 passed / 1 failed | FAIL；global handle 基线测试存在并行隔离问题 |
| Rust `cargo test --lib -- --test-threads=1` | 64 passed | PASS；只证明串行稳定，不可覆盖并行失败 |
| 当前 `jniLibs` hash | `1493d32c5f9f5e66b467803cb804bd4c24993bc5525c9859c2e03e85827ffd48` | 与 APK 不一致 |
| 当前 debug APK hash | `65dd5ae5010f1f14781e1ce6af9566e1ede04e2b4612c6f966101bf7bec36270` | 可定位，但不可证明可复算 |
| debug APK 内 `.so` hash | `80f82bb8fb6fcab30db87ce140248a2ae326a6b39af5a795fa2e48276c18679d` | 与 `jniLibs` 和报告值都不一致 |
| 结果报告/manifest 声称的 packaged `.so` | `1f0391bd31b925e13db0d27e4f6b7ee040a3372eb5804f697484157aa7d73c0c` | 已过时或证据错误 |
| Device A | 1 张卡 debug smoke | PARTIAL |
| 100 卡、release、Device B、RSS/UI stall、跨日矩阵 | 未执行 | NO-GO |

Rust 默认并行失败发生在 `ops::tests::alloc_free_returns_handle_count_to_baseline`：测试观察到 `owned handles leaked mid=27 after=12`。串行运行 64/64 通过，说明更可能是共享全局计数与并行用例互相干扰，而不是已经证明的生产泄漏；但在测试隔离修复、默认命令连续通过前，不得继续把它记录为“64/64 稳定通过”。

### 2.2 Android 截图揭示的实际 UI

`artifacts/p4/device-a-review-question.png` 显示：

- 外层 AppBar：`Official Review`，带 Undo/Redo；
- 内层又有 AppBar：`官方卡片预览`，带返回按钮；
- 内层 Reviewer 有一个“显示答案”；
- 外层正式会话又有一个 `Show Answer`；
- Bury/Suspend 位于外层；
- 页面实际是“正式 Scheduler 外壳嵌套一个完整 Preview 页面”，不是一个统一 Reviewer。

这不是单纯视觉瑕疵。两个按钮分别驱动不同状态：内层按钮驱动 `OfficialAnkiReviewerController.showAnswer()`，外层按钮只调用 `OfficialReviewSession.showAnswer()`。因此用户可以在仍显示正面时让评分按钮出现并提交评分。

### 2.3 P5 实际起点

现场盘点结果：

| 项目 | 当前事实 |
|---|---|
| Legacy 源码规模 | `lib/application/anki` + `lib/views/anki` 共 30 个 Dart 文件，约 14,995 行 |
| 外部生产依赖 | 至少 10 个 Legacy 目录外 Dart 文件直接 import Legacy Anki |
| 正常导入入口 | 仍是 `AnkiImportPage`；flag 全开时由 `AnkiImportFacade` 条件转官方，否则回退 Legacy |
| 正常复习入口 | `AnkiReviewRoute` / `AnkiReviewSessionRoute` 仍使用 `AnkiReviewAssembler` + `SrsProvider` |
| 正式官方复习入口 | 只在 `OfficialAnkiInternalPage` 内部调试页 |
| Release flags | official engine/import/renderer/projection/courseEntry/scheduler 默认全部 `false` |
| P5 元数据 | `engineKind`、`migrationState`、`migratedSourceId` 在生产代码中均不存在 |
| P5 测试/文档 | 本文之前没有 P5 专项测试或实施文档 |
| 官方迁移基础 | official catalog/import Saga/card descriptor/projection 已具备，可作为 P5 基座 |

因此，P5 的“直接阶段实现”按专项目标计为 **0%**；若把 P1–P4 已建设的官方基座算作前置准备，约为 **45%–55%**。两者不能混写成“P5 已完成一半”。

## 3. P4 完工度重新评估

不使用一个模糊总百分比掩盖短板，按可独立验收的能力评估：

| 能力面 | 估算完工度 | 结论 |
|---|---:|---|
| Native scheduler contract / rslib 调用 | 80% | 主操作存在，仍需严格解码、真实 unknown outcome 与压力验证 |
| Dart engine / worker transport | 70% | API 已接入，缺统一协调器、跨 isolate 审计、严格失败策略 |
| Review session 状态机 | 55% | single-flight/elapsed 已有，但 renderer ACK、error/reconcile/undo 状态不完整 |
| 正式 Reviewer UI | 25% | 嵌套 Preview，翻面与评分解耦，正式入口未接生产路由 |
| Android 设备验收 | 15% | 只有 1 卡 debug partial smoke，且 APK/native 身份不闭合 |
| 生产切换与回退 | 0% | 默认 flag false，正常入口仍是 Legacy |

若按上述六个维度等权，仅可视作约 41% 的 P4 生产交付完成度。Host 代码量完成不等于生产链路完成。

## 4. 问题清单与根因

### 4.1 P0：答案呈现与评分授权没有形成同一个事务

证据：

- `OfficialAnkiReviewPage` 内嵌整个 `OfficialAnkiReviewerPage`；后者自身包含 Scaffold、AppBar、flip button 和 controller。
- 外层 `Show Answer` 只执行同步的 `_session.showAnswer`。
- `_session.showAnswer` 只改 `phase` 并启动 Stopwatch，不调用 renderer。
- P4 widget test 注入 `reviewer: const SizedBox(...)`，所以不可能发现真实 Reviewer 没翻面。

风险：正面仍可见时提交 Again/Hard/Good/Easy；`millisecondsTaken` 也不是“答案真正可见的时长”。

修复原则：评分授权必须依赖同一个 Presenter 返回的 `answerPresentedAck`，而不是依赖外层按钮点击事件。

### 4.2 P0：错误态可能被渲染成 Congrats，且异步异常可能冒泡

`refreshQueue()` 失败时可能保留 `current == null` 和 `congrats == null`；页面只根据 `card == null` 渲染 `_CongratsView`。`_open()`、`_run()` 只有 `finally`，没有将 exception 映射为稳定 UI。Undo/Redo/Bury/Suspend 的错误也可能直接冒泡。

修复后必须按 phase 渲染，而不是以 `card == null` 猜测 completed：

```text
opening/loading -> progress
showingQuestion/showingAnswer -> reviewer
reconciling -> blocking reconciliation view
recoverableError/staleContext -> retry view
fatalError -> fail-closed view
completed + congrats != null -> congrats
其他组合 -> invalid-state fail-closed
```

### 4.3 P0：APK、`jniLibs`、报告和设备证据无法互证

当前至少出现 `1493d…`、`80f82b…`、`1f039…` 三个 native hash。artifact 中只记录了 `jniLibs` hash，没有记录从 APK 解包后的 hash，也没有记录从设备安装目录拉取后的 hash。设备 smoke 因而不能回答“测试的究竟是哪一版 native”。

必须形成不可手填的链路：

```text
Rust source commit + submodule commit
  -> built native file hash
  -> copied jniLibs hash
  -> APK internal .so hash
  -> installed device extracted/base APK hash
  -> ENGINE_INFO backendCommit/contract/capabilities
```

五处任一不一致即验收失败。

### 4.4 P1：所谓 runtime Scheduler audit 不能覆盖生产 worker

`OfficialAnkiSchedulerAudit` 是 Dart static 内存计数。生产正式路径通过 worker isolate 调用 FFI，worker isolate 增加的 static 计数不会自动出现在 UI/main isolate 的 snapshot。更严重的是，Turna SRS、Legacy、projection、preview、derived exercise 的 forbidden-write 计数没有生产埋点，只是初始化为 0；“从未增加的计数仍为 0”不能证明路径没有写入。

`OfficialAnkiCanonicalCompletion` 中的：

```dart
assert(officialSchedulerAnswers == officialSchedulerAnswers);
```

是恒真表达式，不提供任何保护。

### 4.5 P1：unknown outcome 只是局部实现，尚非可恢复协议

Native 能用测试 flag 模拟 `ANSWER_COMMIT_UNKNOWN`，并在同一 engine 生命周期内阻止 token 重放；但：

- Dart 收到 unknown 后立即 `refreshQueue()`，`reconciling` phase 很快被覆盖；
- mutation id 与 committed set 只存在内存，Collection reopen 会清空；
- worker 崩溃、FFI 成功提交但 response 序列化/进程传输丢失时，没有持久 receipt；
- UI 没有明确的“正在核对官方状态”与可审计结果。

这足以防住单进程内的一个测试注入分支，不足以证明 process-death exactly-once。

### 4.6 P1：缺少 import / projection / review 的全局操作协调

当前同一 worker 会串行处理消息，但没有显式 `OfficialAnkiOperationCoordinator` 定义生命周期互斥。复习中可以触发 import/reopen/restore，使 token 失效；这可能不造成双写，却会造成不可预测的 stale/error UX。P4 计划中的“复习期间禁止破坏性 Collection 操作”尚未形成可测试策略。

### 4.7 P1：DTO 与 worker 对非法数据存在 fail-open

例子：

- queue/card DTO 对缺字段默认 `0`、空字符串或空 labels；
- `OfficialMutationResult.fromJson()` 把 `ok` 固定为 `true`；
- worker 对未知 bury action 静默回退为 `buryUser`。

跨 FFI/worker 边界的必填字段应严格校验。特别是未知 action 绝不能自动执行另一个写操作，必须返回 `INVALID_ARGUMENT`。

### 4.8 P1：Undo/Redo/Bury/Suspend UI 未按官方能力状态驱动

页面在非 busy 时总是启用 Undo/Redo，没有先读 `GET_UNDO_STATUS`。Bury/Suspend 没有 filtered deck/能力提示、确认或失败态。当前 `burySched` 名称与 UI“Bury”含义也未清楚区分用户 bury、scheduler bury 和 sibling bury。

### 4.9 P1：P2 的 `RENDER_TIMEOUT` 仍穿透到 P4

Device A 首次打开内嵌 Preview 出现 `RENDER_TIMEOUT`。这不是可以延后的纯 P2 问题，因为 P4 正式评分依赖答案正确呈现。正式评分页在 Reviewer 没有 ACK 时必须禁止显示评分按钮。

### 4.10 P2：Rust handle 计数测试有并行隔离缺陷

默认 `cargo test --lib` 会与其他创建 engine handle 的测试并行，导致全局 baseline 断言偶发失败；串行通过不能替代修复。应让该测试独占、按本测试持有的 handles 做精确追踪，或把全局 registry 测试放入串行测试组。

### 4.11 P2：内存幂等集合需要边界

`committed_mutations` 在 Collection open 时清空，但同一次长生命周期中持续增长。100 卡影响很小，长期用户会话需要 TTL、容量上限或随可证明安全的 epoch 清理策略，并用压力测试证明不会失去幂等保护。

## 5. P4 修补包：P4R2

P5 cutover 前必须完成以下修补。任务按依赖顺序执行。

### P4R2-01：统一 Formal Reviewer Presenter（P0）

目标：只有“官方答案面已呈现并 ACK”才能评分。

实施：

1. 从 `OfficialAnkiReviewerPage` 提取无 Scaffold 的 `OfficialAnkiReviewerStage`。
2. Formal 页面持有一个可注入的 `OfficialAnkiReviewerController` 或窄接口 `OfficialAnswerPresenter`。
3. 新流程改为：

```text
queue card
 -> presenter.load/showQuestion ACK
 -> user taps Show Answer
 -> presenter.showAnswer
 -> WebView/native present ACK
 -> session.answerVisibleElapsed.start
 -> phase=showingAnswer
 -> enable rating buttons
```

4. render timeout/error 时保持评分禁用，提供 Retry/Back，不改变 Scheduler。
5. 卡片切换时以 `cardId + generation + side` 防止旧 ACK 解锁新卡。
6. 删除内层 AppBar、内层返回按钮和第二个 flip button。

验收：

- 真实 controller widget/integration test，不允许用 `SizedBox` 替换被测 Presenter；
- 未 ACK、错误 ACK、旧 generation ACK、重复 tap 均不能评分；
- screenshot 只能有一个 AppBar、一个 Show Answer；
- elapsed 从 answer ACK 后开始，不从点击时开始。

### P4R2-02：重写页面状态渲染和错误恢复（P0）

实施：

- 用 `OfficialReviewPhase` 穷尽式渲染 UI；
- completed 必须同时满足官方 queue empty/congrats 已获得；
- 捕获 `_open/_run` 异常并映射 safe error；
- retry 不重放 answer，只重新读取官方 queue；
- stale、unknown、fatal 分屏显示；
- 页面 dispose 时停止 Stopwatch、取消未完成 presenter generation；
- 切卡前禁止旧卡按钮继续提交。

### P4R2-03：可恢复 mutation receipt（P1）

实施方案：

- 在独立 official catalog 新增 `anki_scheduler_mutations`，至少记录 mutation id、card id、queue epoch、rating、state、created/updated time；
- 调用 native 前落 `prepared`，返回成功落 `committed`；
- unknown 落 `unknown`，不自动重答；
- 增加 read-only reconciliation op，以 card/revlog/undo metadata 判断 `committed | notCommitted | unresolved`；
- unresolved 必须阻塞同一卡继续评分，并保留人工恢复信息；
- 为 receipt 做 TTL/compaction，但不得删除 unresolved。

如果不愿在首版承诺 process-death exactly-once，必须把语义明确降级为 at-most-once + unresolved manual recovery，并在 UI/文档中诚实声明。

### P4R2-04：Operation Coordinator（P1）

定义单 profile 状态：

```text
idle | importing | projecting | reviewing | backupRestore | maintenance
```

规则：

- reviewing 与 import/restore/reopen 互斥；
- projection 只能读稳定 snapshot；
- preview 可与 review 共存，但只读；
- UI 导航、worker dispatch 和 native 均做防线，不能只靠按钮禁用；
- 冲突返回稳定 `OPERATION_CONFLICT`，不偷偷 invalid token 后继续。

### P4R2-05：严格 contract 解码（P1）

- 必填 ID 必须 `> 0`；token/session/rating/labels 不得为空；epoch 必须有效；
- `OfficialMutationResult.ok` 读取响应值；
- 未知 enum/action fail-closed；
- response 缺字段返回结构化 contract error；
- 保留 forward-compatible unknown response fields，但不允许缺少 required fields；
- 加 malformed response 和 worker message fuzz/table tests。

### P4R2-06：Undo/Redo/Bury/Suspend 产品语义（P1）

- 进入页面和每次 mutation 后刷新官方 undo status；
- 只有 `canUndo/canRedo` 时启用；
- 明确区分 `Bury card`、`Bury siblings`、`Suspend card`；
- filtered deck 根据官方能力显示支持/不支持原因；
- mutation 成功后强制重新获取 queue/status/counts；
- 不用 Turna review history 模拟 Undo。

### P4R2-07：可信运行时审计（P1）

取消跨 isolate static 计数作为验收依据。改为：

- worker 返回 scheduler write event/receipt，主 isolate 只展示聚合；
- Turna SRS、Legacy write DAO、projection writer 都在边界处记录 path owner；
- 审计事件至少包含 owner、operation、source/card、request id、时间，不包含卡片正文；
- 测试以 spy/deny-write adapter 证明 forbidden writer 没被调用；
- 删除恒真 assert；
- device artifact 由测试程序导出，不手填 JSON。

### P4R2-08：可复算产物与设备门禁（P0）

1. clean build native arm64；
2. copy 到 `jniLibs`；
3. clean build debug/release APK；
4. 自动比较 built/jniLibs/APK/device 四处 `.so` hash；
5. 读取 device `ENGINE_INFO` 并保存 JSON；
6. 运行 Device A 100 卡 debug + release；
7. 运行 Device B；若客观无 Device B，结论保持 NO-GO，不以 waiver 偷换通过；
8. 记录 RSS、P50/P95 render、最大 UI stall、100 卡 revlog delta、duplicate delta；
9. 覆盖跨日、时区、DST、daily limits、filtered deck；
10. 默认并行 Rust 测试连续两次通过。

### P4R2 退出门槛

以下全部满足才可把 P5 从“准备”推进到“用户迁移 pilot”：

- [ ] answer ACK 与评分授权原子绑定；
- [ ] 单一 AppBar/单一 Show Answer；
- [ ] render error 时 Scheduler write = 0；
- [ ] error/reconcile/completed 状态无混淆；
- [ ] unknown outcome 有持久策略；
- [ ] operation coordinator 生效；
- [ ] strict contract/fail-closed tests 通过；
- [ ] 默认并行 Rust 测试连续 2 次通过；
- [ ] 159+ Flutter official tests 扩展后连续 2 次通过；
- [ ] APK/device/native hash 闭环；
- [ ] Device A debug/release 100 卡通过；
- [ ] Device B 通过；
- [ ] P2 `RENDER_TIMEOUT` 在正式路径清零或稳定阻止评分；
- [ ] release flag 仍默认 false，直到单独 production decision。

## 6. P5 目标架构

P5 不是“删除 `lib/application/anki` 文件夹”。它要完成三个可回滚的状态变化：

```text
来源身份：legacy source -> official source
课程投影：legacy word/card identity -> official canonical identity
复习所有权：Turna SRS -> official Collection Scheduler
```

最终规则：

- 官方 Anki Collection 是 Anki 卡片内容、模板、媒体和调度的唯一事实源；
- official catalog 保存来源、导入 Saga、迁移、映射和课程投影元数据；
- CourseDatabase 只保存可重建课程投影，不保存 official scheduling 镜像；
- Turna SRS 只服务原生词汇/语法，不再服务 official Anki Card；
- 每个来源任一时刻只能由一个 engine 负责复习；
- 不做 Legacy/Official 双写；
- 不把不等价的 Turna SRS 历史伪造成官方 revlog。

## 7. P5 数据模型

迁移 registry 应放在独立 `OfficialAnkiDatabase`，不能只放 `CourseDatabase`。后者的 downgrade 策略会清理并重建表，不适合承载不可丢失的迁移事实。

### 7.1 official catalog schema v6 候选

```sql
CREATE TABLE legacy_anki_migrations (
  migration_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  legacy_import_id TEXT NOT NULL,
  official_source_id TEXT REFERENCES anki_sources(source_id),
  state TEXT NOT NULL,
  scheduling_policy TEXT NOT NULL,
  source_hash TEXT,
  backup_id TEXT,
  backup_manifest_hash TEXT,
  legacy_card_count INTEGER NOT NULL DEFAULT 0,
  matched_card_count INTEGER NOT NULL DEFAULT 0,
  unresolved_card_count INTEGER NOT NULL DEFAULT 0,
  cursor_legacy_card_id INTEGER,
  official_mutation_count_at_cutover INTEGER NOT NULL DEFAULT 0,
  started_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT,
  last_error_safe_message TEXT,
  UNIQUE(profile_id, legacy_import_id)
);

CREATE TABLE legacy_anki_card_map (
  migration_id TEXT NOT NULL REFERENCES legacy_anki_migrations(migration_id),
  legacy_card_id INTEGER NOT NULL,
  legacy_word_id TEXT NOT NULL,
  legacy_note_id INTEGER,
  note_guid TEXT,
  template_ord INTEGER NOT NULL,
  official_card_id INTEGER,
  match_method TEXT NOT NULL,
  match_state TEXT NOT NULL,
  content_fingerprint TEXT,
  PRIMARY KEY(migration_id, legacy_card_id)
);
```

不要直接在旧 `anki_imports` 表只加一个 bool。迁移是带 checkpoint、备份、匹配失败和回滚边界的 Saga，需要独立状态和 card-level 证据。

### 7.2 migration state machine

```text
detected
 -> awaitingPackage
 -> validatingSource
 -> backingUp
 -> importingOfficial
 -> indexingOfficial
 -> mappingCards
 -> projectingCourse
 -> verifying
 -> cutoverReady
 -> cutover
 -> observing
 -> completed

任意写阶段 -> failedRecoverable | needsUserAction | rollbackRequired
cutover 前 -> rolledBackLegacy
cutover 后且 official mutation=0 -> rollbackEligible
cutover 后且 official mutation>0 -> noLegacyScheduleRollback
```

未知 state 必须 fail-closed，不能默认成 detected 或 completed。

### 7.3 来源与 Card 匹配顺序

1. `note GUID + template ordinal`；
2. 同一可信 package/collection 下的原 card id；
3. `notetype fingerprint + normalized field fingerprint + ordinal`；
4. 冲突、多匹配、缺 GUID 时进入 `needsUserAction`；
5. 不允许只依赖 `anki-<importId>-c<cardId>` 作为跨引擎永久身份。

每次匹配必须保存 `match_method`。自动 cutover 要求 100% 有唯一匹配；未匹配卡只能显式排除或由用户重新绑定，不能静默丢失。

### 7.4 调度策略

用户只能显式选择：

- `preservePackageScheduling`：重新导入原包中可用的官方 scheduling；
- `resetAsNew`：官方 Core 将目标卡重置为新卡；
- `keepLegacyReadOnly`：暂不迁移，Legacy 只读展示，不能继续双写。

P5 首版禁止：

- 把 Turna `srs_states` / `schedulingJson` 翻译成官方 revlog；
- 根据 Turna interval 猜测 FSRS state；
- 在迁移验证期同时给 Legacy 和 Official 写评分；
- 没有原 `.apkg/.colpkg` 时凭 Legacy 镜像拼装官方 Collection。

## 8. P5 分批实施

### P5-A：只读 Census 与保护栏（现在即可开工）

状态：**允许，不依赖 P4 production GO**。

任务：

- [ ] `P5-A01` 建立 Legacy dependency inventory，列出 30 个文件的角色：import、render、course projection、review、DAO、UI、platform fallback；
- [ ] `P5-A02` 增加只读 `LegacyAnkiCensusService`，统计 source/card/note/media、srs/review event、缺失 source file、重复 GUID、平台；
- [ ] `P5-A03` 输出脱敏 JSON report，不包含卡片正文和媒体；
- [ ] `P5-A04` 引入 `AnkiEngineKind { legacy, official }` 和 `AnkiSourceRouteResolver`，初始全部保持现状；
- [ ] `P5-A05` 对每个 write boundary 加 owner 标签和 deny-write 测试；
- [ ] `P5-A06` 新导入只有在 official 全门禁满足时选 official；否则明确 fail-closed，不再静默混合半套流程；
- [ ] `P5-A07` 为 Android/OHOS/iOS/desktop 输出 capability matrix。

交付物：inventory CSV/MD、census JSON schema、resolver tests、write-owner tests。此批不得改变任何用户来源的 engine。

### P5-B：Migration Registry 与 Dry Run（P4R2 可并行开发）

状态：**允许开发，不允许真实 cutover**。

- [ ] `P5-B01` official catalog schema v6 + forward migration + future-version fail-closed；
- [ ] `P5-B02` migration/card-map DAO 和状态转换 CAS；
- [ ] `P5-B03` backup manifest：Legacy 行数/hash、官方 Collection backup、projection manifest；
- [ ] `P5-B04` dry-run matcher，只读产生 matched/unresolved/collision；
- [ ] `P5-B05` 断点续跑、重复执行幂等、崩溃恢复；
- [ ] `P5-B06` 迁移预览 UI：来源、卡数、调度选择、无法匹配项、磁盘空间；
- [ ] `P5-B07` golden fixtures：Basic/Reverse/Cloze/重复 GUID/缺 GUID/多模板/媒体/Unicode。

退出条件：同一输入 dry-run 两次结果相同；任何 mismatch 都不写 official/legacy scheduling。

### P5-C：单来源 Pilot Migration（必须先通过 P4R2）

状态：**当前 NO-GO**。

单来源事务顺序：

1. 获取 operation coordinator 的 migration lease；
2. 验证 Legacy source 未在 review，记录 census；
3. 要求用户重新选择原 package，并校验 hash/结构；
4. 备份 Legacy 元数据、Turna SRS/ReviewEvents 子集和 official Collection；
5. 使用官方 Import Saga 导入；
6. 构建 official card descriptors；
7. dry-run card map；
8. 100% 唯一匹配或用户明确处理 unresolved；
9. 重建 official course projection；
10. 对比 deck/note/card/media/课程位置/renderer fixture；
11. 写 `cutoverReady`；
12. 原子更新 source route 为 official；
13. 将该 Legacy source 标为只读，不能再写 Turna SRS；
14. 进入 observing，不删除数据。

Pilot 只允许内部 fixture 和无价值测试账号。不得直接迁移唯一一份真实用户数据。

### P5-D：生产入口切换与观察期

前提：Pilot、Device A/B、release P4 均通过。

- [ ] 正常 `AnkiImportRoute` 默认使用 official；Legacy import UI 只显示迁移/恢复入口；
- [ ] 正常 `AnkiReviewRoute` 按 source resolver 路由，official source 进入统一 Formal Reviewer；
- [ ] 首页 due count 按 engine 聚合，但评分严格回到各自 owner；
- [ ] Legacy source 迁移后所有评分、undo、bury、suspend 写入口 deny；
- [ ] release flag 分级：internal 1% -> beta 10% -> 50% -> 100%；
- [ ] 每级观察 crash、unknown mutations、render timeout、mapping mismatch、rollback；
- [ ] 至少跨一个正式版本观察，不能在同一版本切换并删除。

### P5-E：Legacy 删除波次

只有满足第 10 节全部门禁后才能开始。

**Wave 1：断生产引用，不删数据**

- 正常路由不再创建 `AnkiImporter`、`AnkiReviewAssembler`、Legacy renderer；
- 保留只读 export/recovery 工具；
- CI 增加 forbidden import rule，防止新代码重新依赖 Legacy。

**Wave 2：删除自研 Scheduler 写路径**

- 删除 Anki card 对 `SrsProvider` 的评分、Undo、quota 和 flags 写入；
- 删除 `anki_srs_migrator.dart` 和 Legacy Anki review commit 逻辑；
- Turna 原生课程 SRS 保留。

**Wave 3：删除自研 render/import 实现**

- 删除 template renderer、HTML fallback chain、prerendered DOM capture、自研 package decode；
- 保留语言字段 mapping、course projector、media/AV 适配器中仍由新架构使用的部分；
- 每删一组先用 `rg` 证明生产引用为 0，再删文件和 tests。

**Wave 4：schema tombstone**

- Legacy 表先停止写入一个 release；
- 提供用户导出和 rollback 版本兼容说明；
- 只在迁移率、未解决来源和平台门禁均达标后删除表；
- schema 删除必须单独 migration，禁止作为普通 cleanup 混入。

## 9. 平台边界：Android 通过不等于可以全局删 Legacy

当前 official runtime 支持条件集中在 Android/Linux/macOS，正式 Reviewer 使用 Android PlatformView；OHOS 没有等价 official Core/Reviewer 生产链路。Legacy HTML view 对非 Android/iOS 仍提供 stripped-text fallback，现有课程/复习入口也仍是共享 Flutter 代码。

因此 P5 必须二选一并形成产品决策：

1. **全平台迁移**：先补 OHOS official Core、renderer、storage、build 和设备验收，再物理删除共享 Legacy；
2. **Android 先行**：按平台路由 official，但 Legacy 共享实现继续保留给 OHOS，代码只能隔离，不能宣称已删除。

在此决策前，允许 Android 停止 Legacy 写入，不允许删除仍被 OHOS 使用的实现。该限制不是 License 项，而是运行平台能力缺口。

## 10. P5 发布与删除硬门禁

### 10.1 迁移正确性

- [ ] Legacy source 总数 = official migrated + explicit deferred + explicit excluded；
- [ ] 每个自动 cutover source 的 card map 唯一匹配率 100%；
- [ ] note/card/deck/media count 差异有解释且被用户确认；
- [ ] Unicode、Reverse、Cloze、typed answer、MathJax、JS/media fixtures 通过；
- [ ] 课程 section/unit/lesson placement 可复算；
- [ ] migration crash 在每个 checkpoint 可恢复；
- [ ] dry run 不产生任何 scheduling write；
- [ ] 正式迁移不生成伪造 revlog。

### 10.2 所有权与复习

- [ ] 同一 source 永远只有一个 engine writable；
- [ ] official source 的 Turna SRS write = 0；
- [ ] Legacy source 的 official scheduler write = 0；
- [ ] preview/derived course exercise 的 scheduler write = 0；
- [ ] unknown outcome 不自动二次评分；
- [ ] official answer、undo、redo、bury、suspend 全走官方 Collection；
- [ ] 100 卡 session 的 revlog 增量与有效评分数一致。

### 10.3 回滚与数据保护

- [ ] backup manifest 可验证；
- [ ] cutover 前任意状态可回到 Legacy；
- [ ] cutover 后 official mutation=0 可回滚路由；
- [ ] official mutation>0 时禁止把旧 Legacy scheduling 重新设为事实源；
- [ ] rollback drill 至少在两台设备各执行一次；
- [ ] downgrade 不删除 migration registry。

### 10.4 删除门禁

- [ ] 新导入 official 占比 100%；
- [ ] eligible Legacy source 迁移率达到既定发布阈值；
- [ ] unresolved migration = 0，或都有明确 deferred/export 处置；
- [ ] 生产引用扫描为 0；
- [ ] 至少一个正式 release 观察期无 P0/P1；
- [ ] Android/OHOS 平台策略已决策并验收；
- [ ] 有可恢复版本和用户导出路径；
- [ ] 单独的删除 PR、schema PR 和 rollback runbook 已评审。

任何一项未满足，结论保持 `P5 LEGACY DELETION NO-GO`。

## 11. 测试矩阵

| 层级 | 必测内容 |
|---|---|
| Unit | strict DTO、state CAS、identity matcher、route resolver、scheduling policy、unknown state |
| Native | four ratings、revlog delta、undo/redo、filtered deck、daily limit、unknown outcome、mutation compaction |
| Widget | answer ACK 前禁评分、render error 禁评分、单一按钮、error/reconcile/congrats、migration preview |
| Integration | Legacy source dry-run -> backup -> official import -> map -> projection -> cutover -> review |
| Crash recovery | 每个 migration checkpoint、worker death before/after answer commit、app force-stop |
| Differential | bridge 与 pinned rslib card/revlog/deck counts；Legacy/official 只比内容映射，不比不等价 SRS |
| Device | Device A/B、debug/release、100 卡、跨日/时区/DST、RSS、UI stall、首次 WebView |
| Static guard | official 路径禁止 import Legacy writer；课程 preview 禁止 import scheduler writer |

必须新增的关键测试名称建议：

```text
formal_review_does_not_enable_rating_before_answer_present_ack
formal_review_render_timeout_never_writes_scheduler
formal_review_stale_ack_cannot_unlock_next_card
worker_unknown_bury_action_fails_closed
worker_audit_is_visible_across_isolate
parallel_cargo_tests_do_not_share_handle_baseline
legacy_migration_dry_run_is_read_only_and_idempotent
legacy_migration_crash_resumes_every_checkpoint
legacy_source_never_has_two_writable_engines
cutover_with_official_mutation_cannot_restore_legacy_schedule
apk_native_hash_matches_jnilibs_and_device
```

## 12. 建议施工顺序与工期

以 1 名熟悉 Flutter/Rust/Android 的开发者估算，不含应用商店观察等待时间：

| 周期 | 工作包 | 预计 |
|---|---|---:|
| Sprint 1 | P4R2-01/02，统一 Presenter、ACK、错误态 | 4–6 天 |
| Sprint 2 | P4R2-03/04/05，receipt、协调器、strict contract | 5–8 天 |
| Sprint 3 | P4R2-06/07/08，产品语义、审计、产物与设备门禁 | 5–8 天 |
| 可并行准备 | P5-A + P5-B schema/dry-run | 6–10 天 |
| Sprint 4 | P5-C fixture/test-account pilot | 5–8 天 |
| Sprint 5 | P5-D production routing、灰度、rollback drill | 5–8 天 |
| 后续版本 | P5-E 删除与 schema tombstone | 5–10 天 + 至少一个 release 观察期 |

实际编码约 30–50 人日。Device B、OHOS 路线和正式 release 观察是日历时间硬约束，不能通过并行编码消除。

## 13. 首个可执行任务板

下一次施工应直接从下面顺序开始：

```text
NOW-1  提取无 Scaffold 的 OfficialAnkiReviewerStage
NOW-2  定义 OfficialAnswerPresenter + PresentAck
NOW-3  Formal page 用同一 presenter 驱动 question/answer
NOW-4  rating 依赖 answer ACK；删除重复 flip/AppBar
NOW-5  补 4 个真实 presenter widget tests
NOW-6  修 phase/error/congrats 渲染
NOW-7  strict worker bury action + DTO required fields
NOW-8  修 Rust handle test 并行隔离
NOW-9  clean rebuild，生成四段 native hash manifest
NOW-10 建立 P5 Legacy inventory 与只读 census
NOW-11 建 official catalog v6 migration registry
NOW-12 做 dry-run matcher；保持 cutover flag false
```

`NOW-1` 到 `NOW-9` 是 P4R2 收口；`NOW-10` 到 `NOW-12` 是允许提前推进的 P5 准备。不得把后者的完成当作迁移用户数据的授权。

## 14. 最终验收口径

P4 完成的可观察定义：用户从正式入口打开一张官方卡，看到唯一正面，点击唯一 Show Answer，官方答案成功 ACK 后才出现四档官方间隔，评分只产生一条官方 revlog；render error、双击、stale、worker death 和重启均不会产生重复或错误写入，且 APK/native/device 身份可复算。

P5 完成的可观察定义：新导入只进入官方 Collection；已有 Legacy 来源能以可预览、可恢复、无双写的 Saga 迁移到官方来源；课程位置和语言学习投影仍工作；正常复习不再调用 Legacy/Turna Anki Scheduler；经过至少一个版本观察后，才按平台能力分波删除无人使用的 Legacy 代码和 schema。

在达到这两个定义前，正确决策是继续保持：

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false（release default）
P4 PRODUCTION NO-GO
P5 CUTOVER NO-GO
P5 LEGACY DELETION NO-GO
```
