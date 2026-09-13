# Phase 4 官方 Anki Scheduler 实施计划

> 文档代号：P4-SCHEDULER
> 状态：计划冻结；`P4 ENTRY NO-GO / P4 TECHNICAL NO-GO / P4 PRODUCTION NO-GO`
> 制定日期：2026-08-17
> 当前分支：`spike/official-anki-core-android`
> 审计基线：`cc1484b30739bceeba07fe1a3be98b8b0e11018d` + 当前 dirty worktree
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`
> 当前稳定 contract：`1.2`
> P4 目标 contract：`1.3`（候选）
> 首发平台：Android arm64
> 上位计划：`11-p3-remediation-and-phase-4-scheduler-plan.md`
> 前置结果：`10-phase-3-fix-result-report.md` 当前仍为 P3 Technical/Production NO-GO
> 明确排除：License/法律签字、AnkiWeb Sync、Phase 5 Legacy 删除、Turna 自有课程迁移、OHOS/iOS/桌面发布
> 发布原则：所有 P4 硬门禁通过前，`TURNA_OFFICIAL_ANKI_SCHEDULER` 默认且强制为 `false`

## 1. 目的

Phase 4 的目标不是在 Turna 中重新实现一个类似 Anki 的 SRS，而是把 pinned 官方 Anki `rslib`
Scheduler 作为 official Card 的唯一调度引擎，并建立完整、可测试、可回滚的移动端复习链路：

```text
Official Collection
  → official deck/queue/counts
  → official renderer question/answer
  → Again / Hard / Good / Easy
  → official AnswerCard
  → official Card + FSRS/memory state + revlog
  → official Undo/Redo
```

Dart/Flutter 只负责：

- 选择来源和 Deck。
- 展示官方返回的队列、计数和下一间隔标签。
- 通过 Phase 2 Reviewer 显示官方渲染结果。
- 采集用户评分和真实答题耗时。
- 管理移动端页面与生命周期。
- 展示稳定错误和恢复动作。

Dart 不负责：

- 计算 Again/Hard/Good/Easy 的新状态。
- 计算 FSRS、fuzz、learning steps 或 due。
- 自行重建 filtered deck/daily limit 规则。
- 写 official Card scheduling mirror。
- 用 Turna `srs_states` 代替或备份 official Scheduler。

## 2. 当前基线审计

### 2.1 已存在的 Scheduler spike

Rust bridge 已定义并分发 11～16：

| ID | Rust operation | 当前能力 |
|---:|---|---|
| 11 | `SET_CURRENT_DECK` | 调用 `Collection::set_current_deck()` |
| 12 | `GET_REVIEW_QUEUE` | 调用 `get_queued_cards()`，生成内存 answer token |
| 13 | `DESCRIBE_NEXT_STATES` | 对 token 保存的 states 调用官方描述接口 |
| 14 | `ANSWER_CARD` | 使用 token states 调用官方 `answer_card()` |
| 15 | `GET_UNDO_STATUS` | 读取官方 undo/redo availability |
| 16 | `UNDO` | 调用官方 `undo()` |

Host Rust 测试已经覆盖最小 queue → answer → stale token → undo → reopen 路径。这只证明 pinned rslib
可以被调用，不构成稳定 P4 contract 或移动端验收。

### 2.2 当前 spike 的明确缺口

1. `contract/operations.md` 仍把 11～16 标为 reserved，没有发布 request/response。
2. 稳定 Dart `OfficialAnkiOperation` 不包含 Scheduler operations。
3. Scheduler 仅存在 spike models/数字常量，没有 typed DTO、Engine interface、worker command 和 production facade。
4. Native 请求/响应仍使用 snake_case，与稳定 contract 的 camelCase 规则不一致。
5. `ANSWER_CARD` 把 `milliseconds_taken` 固定为 `0`，没有真实答题耗时。
6. answer token 只在 open/close/import 等路径清理；Answer、Undo 和 deck switch 后没有统一 queue epoch。
7. 批量 queue 中后续 token 可能继续引用 mutation 之前计算的 states。
8. token 在调用官方 `answer_card()` 前从 map 删除；失败类别不能区分“肯定未写”与“结果未知”。
9. 没有 production UI，也没有 Again/Hard/Good/Easy 按钮状态机。
10. 没有 Redo、Bury/Suspend、Counts/Congrats stable operation。
11. 没有 App restart、response lost、跨日、时区、daily limits、filtered deck differential tests。
12. 没有证明 official answer 不会同时写 Turna SRS。
13. Android Scheduler capability、debug/release、Device A/B 均没有验收证据。

### 2.3 当前结论

```text
P4 RUST SPIKE: HOST CALLABLE
P4 STABLE CONTRACT: NOT IMPLEMENTED
P4 DART/WORKER: NOT IMPLEMENTED
P4 PRODUCTION UI: NOT IMPLEMENTED
P4 DEVICE ACCEPTANCE: NOT RUN
P4 ENTRY: NO-GO
```

## 3. Entry Gate

### 3.1 必须满足的前置阶段

P4 production 施工入口必须同时满足：

- Phase 1 official import 能在目标 Android 设备稳定 open/import/reopen。
- Phase 2 question/answer、media、AV/TTS、typed、MathJax instrumented tests 通过。
- P3R production composition、job、canonicalLink、mapping、容量和 Device A 门禁通过。
- official worker isolate 是 Collection 的唯一移动端 owner。
- 当前 `.so`、APK、backend pin 和 contract 可以从 clean checkout 重建。
- production flags 默认关闭且 fail closed。

P4 contract/Host 测试允许在 P3R 后半段并行开发，但以下行为禁止提前发生：

- production route 出现评分按钮。
- internal/beta 以外的真实用户 Card 写 revlog。
- scheduler flag 默认开启。
- official answer fallback 到 Legacy 或 Turna SRS。

### 3.2 Entry 决策文件

开始 P4 production UI 前必须生成：

```text
docs/official-anki-migration/artifacts/p3r-p4/p4-entry-decision.txt
```

至少包含：

- git commit 与 dirty 状态。
- P3R 结果报告位置。
- Device A/API/WebView。
- P2/P3 instrumentation 结果。
- `.so`/APK/hash/backend pin/contract。
- `P4 PRODUCTION IMPLEMENTATION ENTRY GO|NO-GO`。

缺少任意设备/产物事实时只能写 NO-GO。

## 4. 范围与非目标

### 4.1 P4 必须交付

- Deck 选择和当前 Deck。
- official new/learning/review queue。
- question → answer → Again/Hard/Good/Easy。
- 官方返回的下一间隔标签。
- 真实答题耗时。
- Card/revlog/FSRS 的官方写入。
- Undo/Redo。
- Bury Card、Bury Siblings、Suspend/Unsuspend。
- CountsForDeckToday 和 CongratsInfo。
- empty queue、daily limits、filtered deck 的受控状态。
- App 重启、worker crash、stale token 和 response lost 对账。
- Device A/B debug/release 和 clean CI。

### 4.2 P4 非目标

- AnkiWeb Sync。
- Browser/Edit Note/Deck options/FSRS 参数编辑器。
- Custom Study 完整 UI。
- Set Due Date、Grade Now、Schedule As New。
- Turna 重新实现 FSRS 或 Scheduler。
- 将 official queue 保存到 CourseDatabase。
- 将 official revlog 镜像成 Turna review history 权威表。
- 删除 Legacy Anki。
- 把 canonicalLink preview 自动变成正式复习。
- 在 WebView 中增加可调用 FFI 的 JavaScript bridge。

这些能力若以后需要，必须使用 31 以后的 append-only operation 和独立计划。

## 5. 不可变数据所有权

| 内容 | 唯一事实源 | P4 是否可写 |
|---|---|---:|
| official Card queue/due/interval | Official Collection | 仅通过官方 Scheduler |
| FSRS memory state | Official Collection | 仅通过官方 Scheduler |
| official revlog | Official Collection | 仅 Answer/Undo/Redo |
| Deck config/daily limits | Official Collection | P4 首版只读 |
| question/answer HTML | Official renderer | 不持久化为事实源 |
| answer token/context | Native 内存 session | 单次、不可持久化 |
| Turna 原生 SRS | Turna `srs_states` | official path 禁写 |
| P3 derived exercise stats | Turna course stats | 不写 official Scheduler |
| P3 mapping/placement | Official catalog | P4 不修改 |
| P3 projection tree | CourseDatabase | P4 不修改 |

三条路径严格分开：

```text
P2/P3 canonical preview → renderer only → scheduler writes 0
P3 derived exercise     → Flutter + course stats → scheduler writes 0
P4 formal review        → renderer + official scheduler → Turna SRS writes 0
```

## 6. Contract 1.3

### 6.1 版本规则

- contract major 保持 1。
- Scheduler 为 additive operations，minor 从 2 升到 3。
- 旧 Dart 1.2 可继续调用 1.2 operations。
- 新 Dart 必须检查 `ENGINE_INFO.capabilities`，不因 minor 数字足够就假定所有 Scheduler 能力存在。
- operation ID 一经写入 fixture 便 append-only，不重排、不复用。
- request/response 使用 camelCase。
- 未知 response 字段忽略；缺少 required 字段 fail closed。

### 6.2 Operation 表

正式发布现有预留编号：

| ID | Operation | Collection | Mutation |
|---:|---|---:|---:|
| 11 | `SET_CURRENT_DECK` | yes | config/current deck |
| 12 | `GET_REVIEW_QUEUE` | yes | no official scheduling write |
| 13 | `DESCRIBE_NEXT_STATES` | yes | no |
| 14 | `ANSWER_CARD` | yes | Card + revlog |
| 15 | `GET_UNDO_STATUS` | yes | no |
| 16 | `UNDO` | yes | official undo |

新增编号：

| ID | Operation | Collection | Mutation |
|---:|---|---:|---:|
| 27 | `REDO` | yes | official redo |
| 28 | `BURY_OR_SUSPEND_CARDS` | yes | Card queue |
| 29 | `COUNTS_FOR_DECK_TODAY` | yes | no |
| 30 | `CONGRATS_INFO` | yes | no |

17～26 已由 backup、page、batch、typed 和 projection 使用，禁止占用。

### 6.3 Engine capability

`ENGINE_INFO` 只有在当前 native 确实实现并通过 contract fixture 时才返回：

```text
SET_CURRENT_DECK
GET_REVIEW_QUEUE
DESCRIBE_NEXT_STATES
ANSWER_CARD
GET_UNDO_STATUS
UNDO
REDO
BURY_OR_SUSPEND_CARDS
COUNTS_FOR_DECK_TODAY
CONGRATS_INFO
```

P4 `allowsOfficialScheduler` 必须至少要求前六项；Redo/actions/counts/congrats 缺失时首版仍为 P4
acceptance NO-GO，不能用隐藏按钮冒充完整交付。

## 7. Typed DTO

### 7.1 SetCurrentDeck

请求：

```json
{
  "deckId": 123
}
```

响应：

```json
{
  "deckId": 123,
  "queueEpoch": 8
}
```

规则：

- deckId 必须为正数并由官方 Collection 验证存在。
- deck switch 后所有旧 answer token stale。
- 不允许 Dart 修改 Deck config 以实现过滤。

### 7.2 ReviewQueue

首版 production 固定 `fetchLimit=1`，从正确性开始；Host/performance 测试允许 1～100。

请求：

```json
{
  "fetchLimit": 1,
  "intradayLearningOnly": false
}
```

响应：

```json
{
  "sessionId": "opaque-session",
  "queueEpoch": 8,
  "newCount": 10,
  "learningCount": 2,
  "reviewCount": 30,
  "cards": [
    {
      "cardId": 123,
      "noteId": 99,
      "deckId": 1,
      "templateOrdinal": 0,
      "queueKind": "review",
      "answerToken": "opaque-token",
      "labels": {
        "again": "1m",
        "hard": "6d",
        "good": "15d",
        "easy": "1mo"
      }
    }
  ]
}
```

Dart 不得收到：

- `SchedulingStates`。
- `SchedulingContext`。
- FSRS memory state。
- current/new state protobuf。
- custom data 内部格式。
- revlog row 或 Collection schema。

### 7.3 DescribeNextStates

请求只接受当前 token：

```json
{
  "sessionId": "opaque-session",
  "queueEpoch": 8,
  "answerToken": "opaque-token"
}
```

响应返回四个官方 label。若 queue 已经包含 labels，UI 可不额外调用，但 operation 必须保留以支持状态刷新
和 contract completeness。Dart 不格式化 interval 数值。

### 7.4 AnswerCard

请求：

```json
{
  "sessionId": "opaque-session",
  "queueEpoch": 8,
  "answerToken": "opaque-token",
  "cardId": 123,
  "rating": "good",
  "millisecondsTaken": 8421,
  "clientMutationId": "opaque-uuid"
}
```

Native 使用 `TimestampMillis::now()` 作为官方 answered-at，不信任 Dart wall clock。`millisecondsTaken` 来自
UI monotonic timer，Native 校验：

- >= 0。
- <= 24 小时的 bounded 上限。
- 可安全转换到官方类型。
- 不再固定为 0。

响应：

```json
{
  "clientMutationId": "opaque-uuid",
  "cardId": 123,
  "rating": "good",
  "queue": "review",
  "revlogCount": 4,
  "queueEpoch": 9,
  "committed": true
}
```

`clientMutationId` 用于 UI/worker 对账，不写进 official schema，也不能单独作为“已经提交”的证据。

### 7.5 UndoStatus、Undo、Redo

状态：

```json
{
  "canUndo": true,
  "canRedo": false,
  "undoLabel": "Review",
  "redoLabel": null
}
```

Undo/Redo mutation 响应包含新 queueEpoch。Dart 不解释上游内部 change 类型，只刷新 queue/card/counts。

### 7.6 Bury/Suspend

请求：

```json
{
  "mode": "buryUser",
  "cardIds": [123],
  "noteIds": []
}
```

stable mode：

```text
suspend
burySched
buryUser
restoreCards
unburyDeckAll
unburyDeckSchedOnly
unburyDeckUserOnly
```

若一个 operation 无法安全表达所有 restore/unbury 变体，拆为 31+ append-only operation，不把任意字符串
直接传给 rslib。

### 7.7 Counts/Congrats

Counts：

```json
{
  "deckId": 123,
  "new": 10,
  "review": 30
}
```

Congrats 至少包含：

```text
learnRemaining
secsUntilNextLearn
reviewRemaining
newRemaining
haveSchedBuried
haveUserBuried
isFilteredDeck
deckDescription
```

UI 只根据官方 Congrats 判断“完成”“等待学习卡”“受 limit 限制”，不以本地 queue list 为空代替。

## 8. Stable 错误模型

新增错误：

```text
QUEUE_EMPTY
SCHEDULING_CONTEXT_STALE
ANSWER_FAILED
ANSWER_COMMIT_UNKNOWN
UNDO_UNAVAILABLE
REDO_UNAVAILABLE
DECK_NOT_FOUND
SCHEDULER_BUSY
SCHEDULER_CAPABILITY_MISSING
```

分类：

| 错误 | recoverable | UI 行为 |
|---|---:|---|
| QUEUE_EMPTY | yes | 请求 Congrats |
| SCHEDULING_CONTEXT_STALE | yes | 丢弃 token，重取 queue |
| ANSWER_FAILED（确认未写） | yes | 保留 answer frame，可重试/刷新 |
| ANSWER_COMMIT_UNKNOWN | reconciliation | 禁止自动重答，查询 Card/revlog/undo |
| UNDO/REDO_UNAVAILABLE | no-op | 刷新状态，禁用按钮 |
| DECK_NOT_FOUND | no | 返回 Deck 选择 |
| SCHEDULER_BUSY | yes | 等待当前 mutation 完成 |
| CAPABILITY_MISSING | no | fail closed |

错误响应不得包含 raw fields、HTML、SQL、Collection 路径或 panic backtrace。debugDetails 必须 bounded，且仅在
诊断 flag 开启时显示。

## 9. Native Session 和 Token 设计

### 9.1 AnswerToken

Native 内部保存：

```text
tokenId
engineHandle identity
sessionId
queueEpoch
cardId
SchedulingStates
SchedulingContext（若 pinned API 要求）
issuedAt monotonic instant
consumption state
```

只把 opaque token string 返回 Dart。

### 9.2 Queue epoch

以下操作增加 epoch 并清空旧 tokens：

- open/reopen/close Collection。
- import/restore backup。
- SetCurrentDeck。
- Answer success。
- Undo/Redo success。
- Bury/Suspend/restore/unbury success。
- worker/engine session 重建。

读取 render、counts、congrats 不增加 epoch。

### 9.3 单次消费

- UI 同时只能有一个 `ANSWER_CARD` in flight。
- Native 以 `pending → committed|failed|unknown` 管理 token，不在调用官方 API 前无条件删除全部证据。
- committed token 再次调用返回 stale/duplicate，不重复 revlog。
- failed 且确认官方事务未提交时允许显式重试。
- unknown 时进入 reconciliation，不允许后台自动重答。

### 9.4 每题刷新策略

P4 首版每次只消费一张 queued card：

```text
GET_REVIEW_QUEUE(fetchLimit=1)
→ render current card
→ answer
→ invalidate epoch
→ GET_REVIEW_QUEUE(fetchLimit=1)
```

不复用回答之前批量生成的其他 answer token。后续如需 prefetch，只能预取 renderer/media，不预取可提交的
Scheduler context。

## 10. Collection 协调器

增加 `OfficialAnkiOperationCoordinator`，所有 production official 操作声明 access type：

```text
readRender
readProjection
writeImport
writeScheduler
maintenanceBackupRestore
```

规则：

- 同一 profile 只有一个 worker/Collection handle owner。
- Scheduler mutation 全部串行。
- formal review 期间禁止 import/restore；UI 给出明确提示。
- projection read 可排队，不能使 answer context 穿越 Collection generation 变化。
- backup/restore 必须在 review session 结束且无 mutation in flight 时执行。
- worker crash 后所有 token stale，页面重新建立 session。
- 不用多个 FFI handle 绕过 Collection lock。

## 11. Flutter Review 状态机

### 11.1 状态

```text
idle
→ openingCollection
→ selectingDeck
→ loadingQueue
→ renderingQuestion
→ showingQuestion
→ renderingAnswer
→ showingAnswer
→ committingAnswer
→ reconciling（仅 outcome unknown）
→ refreshingQueue
→ completed

任意非终态
  ├─ recoverableError
  └─ fatalError
```

### 11.2 不变量

- showingQuestion 时评分按钮不可用。
- Show Answer 只能触发一次 answer render。
- showingAnswer 才启动/结束明确的回答计时策略；总耗时定义必须固定并写测试。
- committingAnswer 时 Show Answer、评分、Undo、Bury、back gesture mutation 全禁用。
- Answer 成功后才进入下一题。
- stale token 自动重载 queue，但不自动提交同一 rating。
- response lost 进入 reconciling，不显示“回答失败请重试”诱导重复写。
- widget rebuild、横竖屏和 App lifecycle 不创建第二个 session controller。
- dispose 取消 UI subscription，不直接关闭共享 worker。

### 11.3 生命周期

| 事件 | 行为 |
|---|---|
| background at question | 保留 UI 或重取 render，token仍须验证 |
| background at answer | 返回后验证 session/epoch |
| background during commit | 等 worker 结果或进入 reconciliation |
| process killed before commit | 无官方写入，重启取 queue |
| process killed after native commit | 重启取 queue/revlog，禁止重放 |
| engine reopened | 丢弃所有 UI token，重取 queue |

answer token 不写 SharedPreferences、CourseDatabase、catalog 或 restoration state。

## 12. 正式复习 UI

### 12.1 Route 分离

```text
OfficialAnkiPreviewPage
  - 指定 cardId
  - question/answer preview
  - 无评分按钮
  - Scheduler writes 0

OfficialAnkiReviewSessionPage
  - 指定 source/profile/deck
  - 从 official queue 获取 card
  - 四档评分
  - official Scheduler writes
```

P3 canonicalLink 只能进入 Preview route。不能因为 scheduler flag 开启而自动显示评分按钮。

### 12.2 页面结构

```text
AppBar: Deck / counts / Undo
Progress: new · learn · review
Reviewer frame: official question/answer HTML
AV controls: official sound/TTS
Primary action: Show Answer
Answer actions: Again / Hard / Good / Easy
Secondary: Bury / Suspend / More
Completion: official Congrats
```

### 12.3 评分按钮

- label 使用官方本地化 interval description。
- rating 固定枚举，不按字符串位置映射。
- double tap 只发送一个 mutation。
- commit 前显示明确 busy 状态。
- commit 成功后按钮消失并重取 queue。
- accessibility 给出 rating 和 interval 完整语义。
- typed answer 比较只帮助显示答案，不自动选择 Scheduler rating。

### 12.4 AV、媒体和 WebView 安全

- 复用 P2 `anki.local` media origin、Range、IRI 和 CSP。
- 无 JS/native Scheduler bridge。
- WebView 不能直接提交 rating。
- WebView navigation/new window/download/file access 继续禁止。
- question/answer frame 只接收当前 card/frame token。
- AV 播放失败不改变 Scheduler 状态。

## 13. Undo、Redo、Bury 和 Suspend

### 13.1 Undo/Redo

- Answer 后刷新官方 UndoStatus。
- Undo/Redo 按钮只能在无 mutation in flight 时启用。
- 成功后清空 HTML/token，重新请求 queue/render/counts。
- 不通过删除 Turna analytics 行模拟 Undo。
- 非权威 analytics 可记录 `officialReviewUndone` 事件，但不得作为 Card 状态依据。

### 13.2 Bury

- 明确区分 user bury 和 scheduler bury。
- “Bury siblings”按官方 Note/Card 语义调用 backend，不在 Dart 查 sibling mirror。
- Unbury 通过官方 deck/mode API。
- mutation 后刷新 queue/counts/congrats。

### 13.3 Suspend

- Suspend/Unsuspend 有确认提示。
- Card IDs/Note IDs bounded、去重、为正数。
- 当前 Card suspend 后离开 session。
- 不删除 Card、不删除 P3 projection；下一次投影可继续引用 canonical card，但 formal queue 不返回 suspended Card。

## 14. Counts、Congrats 和首页聚合

### 14.1 Official counts

- Deck 页面通过官方 CountsForDeckToday 获取。
- session header 使用当前 queue response counts。
- Answer/Undo/Redo/Bury/Suspend 后重新取 counts。
- 不从 Turna lesson/card list 统计 official due。

### 14.2 首页

可展示：

```text
Turna 今日复习：N
Official Anki：M
```

允许视觉上显示合计，但：

- 两个数保持不同 label。
- 点击分别进入 Turna SRS 和 Official Review route。
- 不把 M 写入 Turna `srs_states`。
- official engine/capability unavailable 时显示受控不可用，不显示伪造的缓存数。

### 14.3 Congrats

完成页直接解释官方字段：

- 学习卡稍后到期。
- 新卡/复习卡因 limit 仍剩余。
- filtered deck 状态。
- 存在 user/scheduler buried Card。

不得用 `cards.isEmpty` 单独判断今日完成。

## 15. 禁止双写

### 15.1 写入顺序

```text
Native official Answer commit
→ 返回 committed result
→ UI state advances
→ best-effort Turna analytics/XP event（非 SRS）
```

analytics 失败不得回滚 official answer；official answer 失败不得先写 analytics 成功。

### 15.2 禁止调用

P4 official route 不得调用：

- `AnkiSrsMigrator`。
- Legacy `AnkiReviewCommitService`。
- Turna `SrsProvider` scheduling mutation。
- `anki_practice_projections` 作为答案权威。
- P3 projection publish/delete。

P3 preview/derived route 不得调用 P4 `answerCard()`。

### 15.3 Runtime counters

Debug/test 计数：

```text
officialSchedulerAnswers
officialSchedulerUndo
officialSchedulerRedo
officialSchedulerBurySuspend
turnaSrsWritesFromOfficialPath
legacyCallsFromOfficialPath
projectionWritesDuringOfficialReview
officialSchedulerWritesFromPreview
officialSchedulerWritesFromDerivedExercise
```

硬门禁：

```text
formal rating → exactly 1 official answer
Turna SRS writes from official path = 0
Legacy calls from official path = 0
projection writes during formal review = 0
preview/derived official scheduler writes = 0
```

## 16. Response Lost 和 Reconciliation

### 16.1 问题

FFI/native transaction 可能已经提交 Card/revlog，但 worker isolate 或 UI 在接收 response 前终止。此时把它当
普通 `ANSWER_FAILED` 并自动重试会生成第二条 review。

### 16.2 对账信息

Native 在 answer 前记录 bounded 内存 probe：

- cardId。
- pre-answer revlog count/last id summary。
- queue epoch。
- clientMutationId。

重连后 reconciliation 通过官方/bridge 受控 API 查询：

- Card 当前公共 scheduling state 摘要。
- revlog count/last rating/timestamp 的 bounded 摘要。
- UndoStatus。

不得把任意 revlog SQL 暴露 Dart。若无法可靠判断：

- 停止自动答题。
- 刷新 queue。
- 展示“复习状态已刷新，请确认当前卡状态”。
- 写稳定诊断 `ANSWER_COMMIT_UNKNOWN`。

### 16.3 幂等边界

`clientMutationId` 只帮助同一 worker session 去重；official Collection 没有 Turna mutation-id 字段，因此跨
进程幂等必须依靠重新读取官方事实，而不是声称有永久 exactly-once key。

## 17. Restart、跨日和 Filtered Deck

### 17.1 Restart

- 不恢复 answer token。
- reopen Collection 后建立新 session/epoch。
- 重取 current deck、queue、counts 和 Congrats。
- question/answer HTML 可重新渲染，不从持久化 frame 当权威。

### 17.2 时间

测试：

- 23:59 → 次日。
- timezone 变化。
- DST 正/反向跳变。
- device wall clock 大幅修改。
- intraday learning 到期。
- answered elapsed 0、正常值、上限、非法负数/溢出。

Scheduler timing 由官方 backend 决定；Dart timer 只提供答题耗时。

### 17.3 Daily limits

- Queue/counts/congrats 均用官方结果。
- UI 不自行把 remaining card 添加回 queue。
- P4 首版不修改 daily limit。
- limits 导致空队列时显示官方解释，不提示“数据库没有卡片”。

### 17.4 Filtered Deck

- 覆盖 preview filtered 与 rescheduling filtered state。
- 四档结果与官方 direct rslib differential 一致。
- unsupported action fail closed。
- P4 首版不提供 rebuild/empty filtered deck UI，除非另立 operation 和测试。

## 18. Feature flag

新增字段：

```dart
OfficialAnkiFeatureFlags.scheduler
```

环境变量：

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false
```

gate：

```dart
allowsOfficialScheduler =
  engine &&
  import &&
  catalogReady &&
  runtimeCapable &&
  platformReady &&
  renderer &&
  scheduler;
```

Scheduler 不依赖 `projection`/`courseEntry`，但必须从 official source/profile/deck route 进入。

| Renderer | Scheduler | 行为 |
|---:|---:|---|
| 0 | 0 | 无 official review |
| 0 | 1 | fail closed，flag 配置错误 |
| 1 | 0 | 仅 preview，无评分 |
| 1 | 1 | capability 齐全后允许 formal review |

release 默认值始终 false，直到结果报告作出单独的发布决策。

## 19. 分阶段施工任务

### P4-000：冻结基线和 Entry Decision

- 收集 P3R、P2 device、native/APK/contract/pin 证据。
- 保存 Scheduler spike 源码和测试基线。
- 输出 P4 entry decision。
- 未通过时允许 Host contract 分支施工，不允许 production UI 写 Scheduler。

### P4-010：发布 contract 1.3 operation 表

- 更新 `contract/VERSION`。
- 发布 11～16 和 27～30。
- 生成 request/response/error golden fixtures。
- 更新 ENGINE_INFO capabilities。
- 验证旧 1.2 Dart 与新 native 的兼容读取。

### P4-011：实现 Native typed DTO 和稳定错误

- camelCase serde DTO。
- bounded field/card list/fetchLimit。
- opaque session/token。
- Scheduler error code → messageKey/recoverable。
- 移除 production 对 spike JSON 的依赖。

### P4-012：实现 queue epoch 和 token 单次消费

- mutation/deck/lifecycle invalidation。
- production fetchLimit=1。
- duplicate/stale/wrong-card tests。
- 不复用 mutation 前批量 states。

### P4-013：修复 Answer timing 和 outcome

- 真实 monotonic elapsed。
- Native authoritative answered-at。
- committed/failed/unknown 分类。
- clientMutationId session 去重。
- response lost reconciliation。

### P4-014：实现 Undo/Redo

- stable UndoStatus DTO。
- official Undo/Redo。
- mutation 后刷新 queue epoch。
- revlog/Card differential。

### P4-015：实现 Bury/Suspend/Counts/Congrats

- typed action enum。
- card/note/deck validation。
- official counts/congrats。
- filtered deck capability handling。

### P4-020：扩展 Dart contract 和 Engine interface

补齐：

- operation constants/IDs。
- DTO decode/validation。
- error enum/mapping。
- Engine interface。
- FFI transport。
- worker commands。
- fake engine。
- session facade。

### P4-021：实现 OperationCoordinator

- 一个 profile/worker/Collection owner。
- import/review/restore 互斥。
- Scheduler single-flight mutation。
- worker crash/reopen token invalidation。

### P4-022：实现 OfficialReviewSession

- 完整状态机。
- lifecycle/retry/reconciliation。
- real elapsed timer。
- no double submit。
- queue/counts/congrats refresh。

### P4-023：实现正式 Review UI

- Deck 选择。
- question/answer。
- four ratings/official labels。
- AV/TTS/typed/MathJax。
- accessibility/rotation/theme/font scale。

### P4-024：实现 Undo/Redo/Bury/Suspend UI

- action availability。
- confirm scope。
- busy lock。
- mutation 后重新取 queue/render。

### P4-025：接入 Counts、Congrats 和首页

- official/Turna due 分开。
- empty/limit/learn waiting 状态。
- 不缓存伪造 counts。

### P4-030：落实路由与禁止双写

- Preview/Formal Review route 分离。
- canonicalLink 永远 preview。
- official path 不写 Turna SRS。
- runtime counters + DB before/after assertions。

### P4-031：实现 restart/response-lost 对账

- token 不持久化。
- commit unknown probe。
- process kill points。
- no automatic replay。

### P4-032：补齐时间、limits 和 filtered deck

- cross-day/timezone/DST。
- intraday learning。
- daily new/review limits。
- filtered preview/rescheduling differential。

### P4-040：Native differential suite

使用同一 fixture 的两个独立副本：

```text
A: bridge operations
B: direct pinned rslib public API
```

执行相同操作序列，比较公共状态和 revlog 摘要。

### P4-041：Flutter/Kotlin/Android 自动化

- contract golden。
- worker serialization。
- session state machine。
- widget route/actions。
- WebView question/answer protocol。
- Kotlin JVM host/channel tests。
- connected instrumentation。

### P4-050：Device A debug/release

- mixed 100-card session。
- four ratings/Undo/Redo/bury/suspend。
- background/kill/restart/rotate/low-memory。
- performance/RSS/UI heartbeat。
- scheduler/Turna write audit。

### P4-051：Device B 和 clean CI

- 不同 API/WebView。
- 20-card + Undo + restart smoke。
- clean checkout build/test/hash/capability probe。

### P4-052：结果报告和发布决策

输出：

```text
13-phase-4-result-report.md
artifacts/p4/artifact-manifest.txt
artifacts/p4/final-decision.txt
```

未通过任意硬门禁必须写 Technical/Production NO-GO。

## 20. Differential 测试矩阵

### 20.1 Queue

- New。
- Learning steps。
- Review。
- Relearning。
- Intraday learning only。
- Empty。
- Deck/subdeck selection。
- Daily new/review limit。
- Filtered preview/rescheduling。

### 20.2 Ratings

- Again。
- Hard。
- Good。
- Easy。
- 每档 Card queue/due/interval/reps/lapses/memory state 公共摘要。
- 每档 revlog rating/duration 摘要。
- official interval labels。

### 20.3 Context

- valid token。
- token duplicate。
- token wrong card。
- token after Answer。
- token after Undo/Redo。
- token after deck switch。
- token after import/reopen。
- token from another engine/session。

### 20.4 History/actions

- Answer → Undo。
- Answer → Undo → Redo。
- multiple Answer → multiple Undo/Redo。
- empty Undo/Redo。
- bury user/sched。
- bury siblings。
- suspend/unsuspend。
- unbury modes。

### 20.5 Failure injection

- before native answer。
- inside official answer error。
- after Collection commit/before response encode。
- response encoded/worker dies before UI receive。
- UI receives/analytics fails。
- Collection locked。
- backend panic boundary。
- oversized/corrupt response。

## 21. Android 设备验收

### 21.1 Device A 功能

- Cold open Collection。
- Deck/counts。
- New/Learn/Review/Relearn。
- question/answer flip。
- Again/Hard/Good/Easy。
- typed comparison。
- audio/video/TTS。
- image/custom font/MathJax。
- Undo/Redo。
- bury/suspend。
- Congrats/limits。
- background/foreground。
- process kill/restart。
- rotation/theme/font scale。

### 21.2 Device A 性能候选门禁

| 指标 | 门禁 |
|---|---:|
| warm queue fetch p95 | <= 500 ms |
| answer commit p95 | <= 500 ms |
| first question render p95 | <= 1.5 s，不含未缓存远端内容 |
| UI isolate stall | 无 >= 500 ms |
| 100-card RSS 增量 | <= 120 MB，结束后回落 |
| duplicate revlog | 0 |
| leaked native handles | 0 |
| Turna SRS writes | 0 |

指标若因目标设备性能需要调整，必须在运行前冻结理由，不能看到结果后放宽。

### 21.3 Device B

- 不同 Android API。
- 不同 System WebView 版本。
- 20 张 mixed review。
- Undo + restart。
- AV/MathJax/typed smoke。
- scheduler write audit。

## 22. 自动化命令

候选命令：

```bash
PROTOC=/absolute/path/to/native/turna_anki_core/tools/protoc/bin/protoc \
  cargo fmt --manifest-path native/turna_anki_core/Cargo.toml -- --check

PROTOC=/absolute/path/to/native/turna_anki_core/tools/protoc/bin/protoc \
  cargo clippy --manifest-path native/turna_anki_core/Cargo.toml --all-targets -- -D warnings

PROTOC=/absolute/path/to/native/turna_anki_core/tools/protoc/bin/protoc \
  cargo test --manifest-path native/turna_anki_core/Cargo.toml --lib

flutter analyze --no-pub lib/application/anki_official \
  lib/views/anki_official test/application/anki_official

flutter test --no-pub test/application/anki_official \
  test/views/lesson/renderers/show_word_test.dart

cd android
./gradlew :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest

flutter build apk --debug
flutter build apk --release
```

所有命令记录：cwd、环境变量、commit、exit code、test count、duration。环境缺少 `protoc`、设备或权限必须
写“环境阻断”，不能伪装成测试通过或产品失败。

## 23. 安全门禁

- WebView 无通用 native bridge。
- Scheduler API 只由 Dart worker facade 调用。
- token 不进入 HTML/JS/log/analytics。
- error/log 不含 raw fields、HTML、路径和 scheduling state。
- Card/Note/Deck ID 验证为正数且 bounded。
- operation response <= 8 MiB；queue 目标远低于上限。
- Bury/Suspend 列表 bounded。
- Collection path 继续受 allowed root 约束。
- 不开放 file URL、download、new window 或任意 navigation。
- renderer CSP/media origin 不因 P4 放宽。

## 24. 可观测性

事件使用 ID/count/duration，不记录卡片内容：

```text
official_review_session_started
official_queue_loaded
official_question_rendered
official_answer_shown
official_rating_committing
official_rating_committed
official_rating_outcome_unknown
official_queue_stale
official_undo_committed
official_redo_committed
official_bury_suspend_committed
official_review_completed
```

指标：

- queue/render/answer p50/p95/max。
- stale token count。
- duplicate click suppressed count。
- reconciliation count/result。
- worker restart count。
- Scheduler answers/revlog delta。
- Turna SRS/Legacy/projection unexpected writes。

## 25. 备份和回滚

### 25.1 备份

以下操作前创建官方 backup/checkpoint：

- backend pin/contract 升级首次打开用户 Collection。
- Collection schema 可能升级。
- import/restore/Legacy migration。

正常每题复习不创建完整 backup，使用官方 Undo/Redo。

### 25.2 功能回滚

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false
```

关闭后：

- 不创建新 formal review session。
- 已合法提交的 Card/revlog 保留，不自动 Undo。
- Preview 可按 renderer flag 继续工作。
- P3 derived course 不受影响。
- 不把 official scheduling 状态复制回 Turna SRS。

### 25.3 禁止行为

- 不覆盖仍打开的 Collection 文件。
- 不删除唯一 backup。
- 不因 UI 回滚而清空 revlog。
- 不把 official Card reset 为 new 作为“回滚”。
- 不 fallback Legacy Scheduler。
- 不在用户不知情时重放上一次 rating。

## 26. Feature rollout

1. Host-only：contract/native tests；APK capability 存在，scheduler flag false。
2. Internal Device A：测试 profile/source，显式开启。
3. Internal Device B：兼容性和 lifecycle。
4. Beta opt-in：清楚标记“正式写入 Anki 复习记录”。
5. Stable candidate：Technical GO 后仍默认 false，观察 crash/reconciliation。
6. Stable default：另行发布决策，不由本计划自动授权。

每一级都必须支持一键关 scheduler flag，但关闭 flag 不撤销用户已完成的复习。

## 27. 完成检查表

### 27.1 Entry

- [ ] P2 Device A/WebView 验收通过。
- [ ] P3R Technical Acceptance GO。
- [ ] clean native/APK 可复算。
- [ ] P4 entry decision = GO。

### 27.2 Contract/Native

- [ ] contract 1.3 发布 11～16、27～30。
- [ ] request/response/error fixtures 齐全。
- [ ] capabilities 与实现一致。
- [ ] snake_case spike payload 已退出 production。
- [ ] opaque token 绑定 handle/session/epoch/card。
- [ ] mutation 后旧 token stale。
- [ ] Answer 使用真实 elapsed。
- [ ] duplicate answer 不增加第二条 revlog。
- [ ] committed/failed/unknown 可区分。
- [ ] Undo/Redo/Bury/Suspend/Counts/Congrats 使用官方 API。
- [ ] differential tests 全绿。

### 27.3 Dart/Worker

- [ ] stable DTO/error/operation 完整。
- [ ] Engine/FFI/worker/fake/facade 完整。
- [ ] production 不引用 spike models。
- [ ] OperationCoordinator 串行 mutation。
- [ ] worker restart 使 UI token stale。

### 27.4 UI

- [ ] Preview 和 Formal Review route 分离。
- [ ] question/answer/four ratings/labels 完整。
- [ ] real elapsed timer 完整。
- [ ] no double submit。
- [ ] Undo/Redo/Bury/Suspend 完整。
- [ ] Counts/Congrats/limits 完整。
- [ ] AV/TTS/typed/MathJax 完整。
- [ ] lifecycle/reconciliation 完整。

### 27.5 Ownership

- [ ] formal answer exactly one official Scheduler write。
- [ ] official path Turna SRS writes = 0。
- [ ] official path Legacy calls = 0。
- [ ] formal review projection writes = 0。
- [ ] preview/derived Scheduler writes = 0。

### 27.6 发布

- [ ] Device A debug/release 100-card 通过。
- [ ] Device B 20-card/Undo/restart 通过。
- [ ] cross-day/timezone/DST 通过。
- [ ] daily limits/filtered deck 通过。
- [ ] 性能/RSS/UI stall 达标。
- [ ] clean CI 通过。
- [ ] scheduler flag 默认 false。
- [ ] result report/artifact manifest/decision 完整。

## 28. 风险登记

| 风险 | 概率 | 影响 | 主要门禁 |
|---|---:|---:|---|
| Spike 被误当稳定 contract | 高 | 高 | P4-010/011 |
| elapsed 固定 0 | 当前事实 | 中 | P4-013 |
| token 重复提交 | 中 | 极高 | epoch + single-flight + revlog diff |
| Answer 已写但 response 丢失 | 中 | 极高 | commit unknown reconciliation |
| 批量 states 在上一题后过期 | 中 | 高 | production fetchLimit=1 |
| official/Turna SRS 双写 | 中 | 极高 | route ownership/runtime counters |
| canonical preview 意外出现评分 | 中 | 高 | route separation tests |
| filtered/daily limit 被 Dart 重算 | 中 | 高 | official counts/congrats/differential |
| worker/import/review 并发 | 中 | 极高 | OperationCoordinator |
| WebView 获得 native Scheduler 权限 | 低 | 极高 | no JS bridge/security tests |
| 无设备证据提前开 flag | 高 | 极高 | P4-050/051 hard gate |
| dirty worktree 无法复算 | 高 | 高 | baseline + topic commits + clean CI |

## 29. 建议提交切分

1. `docs(anki): freeze phase 4 scheduler implementation plan`
2. `feat(anki): publish scheduler contract 1.3 operations`
3. `fix(anki): replace scheduler spike payloads with typed dto`
4. `fix(anki): bind answer tokens to queue epochs`
5. `fix(anki): record real official answer elapsed time`
6. `fix(anki): reconcile unknown official answer outcomes`
7. `feat(anki): expose official undo and redo`
8. `feat(anki): expose official bury suspend counts and congrats`
9. `feat(anki): add typed scheduler api to dart worker`
10. `feat(anki): serialize official collection operations`
11. `feat(anki): implement official review session state machine`
12. `feat(anki): build formal official scheduler reviewer ui`
13. `feat(anki): add official review actions and completion states`
14. `fix(anki): enforce official and turna srs ownership boundaries`
15. `test(anki): add scheduler differential and failure injection suite`
16. `test(anki): verify scheduler restart time and filtered decks`
17. `test(anki): record android scheduler release evidence`
18. `docs(anki): publish phase 4 scheduler result and decision`

一个提交只处理一个可回滚主题；不得混入非 Anki analyzer、依赖镜像漂移或其他用户修改。

## 30. 工期

| 工作包 | 工程日 |
|---|---:|
| Entry/baseline/contract freeze | 2～3 |
| Native typed DTO/token/answer | 4～6 |
| Undo/Redo/actions/counts/congrats | 3～5 |
| Dart Engine/worker/coordinator | 3～5 |
| Review session/UI | 5～8 |
| Reconciliation/time/filtered/differential | 4～7 |
| Device A/B/release/CI/report | 3～5 |

预计 **24～39 工程日**。不含 P3R 尚未完成的工期、License、上游 pin 升级、AnkiWeb Sync、Phase 5
Legacy 删除和等待实体设备/CI 的排队时间。

## 31. 最终完成定义

Phase 4 只有在以下事实同时成立时完成：

1. Scheduler 11～16、27～30 是 contract 1.3 的稳定 typed operations。
2. Dart 不接触 SchedulingStates/Context，所有 queue/rating 语义来自 pinned rslib。
3. Answer 使用真实 elapsed，token 单次消费，重复点击不会重复 revlog。
4. response lost 不自动重答，能够对账或安全刷新。
5. 正式 Review 与 Preview/P3 derived route 清楚分离。
6. Again/Hard/Good/Easy、Undo/Redo、Bury/Suspend、Counts/Congrats 完整。
7. restart、跨日、时区、daily limits 和 filtered deck 与 direct rslib 差分一致。
8. official formal review 不写 Turna SRS；preview/derived 不写 official Scheduler。
9. Device A/B debug/release、性能、RSS、UI stall 和 clean CI 有可复算证据。
10. production scheduler flag 仍默认 false，结果报告给出真实 GO/NO-GO。

在此之前，正确状态始终是：

```text
P4 HOST CONSTRUCTION ALLOWED AFTER ENTRY REVIEW
P4 TECHNICAL ACCEPTANCE NO-GO
P4 PRODUCTION NO-GO
```
