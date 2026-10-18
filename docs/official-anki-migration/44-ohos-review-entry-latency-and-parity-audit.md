# 鸿蒙复习入口：时延、打扰与安卓对齐审查（2026-10-18）

> 范围：**只审「用户点复习 → 首卡可读」这一段**，以及两平台复习面的形态差异。
> 不重述步 5b 的渲染 / 翻卡 / 评分落库能力（那些已有真机收据，见
> [34 收据](./34-cutover-receipt.md)「鸿蒙步 5b 真机首卡收据」）。
> 本文是**审查与方案**，不是收据；任何一条优化在真机复验前都不改变
> [34 收据](./34-cutover-receipt.md) 的 Held 口径。

## 0. 结论先行

1. **复习器本身能跑，进入复习这一段是当前体验最差的一段。**
   一次点击要穿过 **9 个阶段，其中 8 段阻塞首屏**；两段（批次全量渲染、
   ability 冷启动）完全不互相依赖，却严格排队。
2. **最贵的一段是「整批渲染」**：`OfficialFormalReviewProductionLoader.load`
   在交出第一张卡之前，把队列里**全部**卡逐张 `renderer.render`（当前队列抓取
   上限 100，见 `OfficialAnkiOperation.maxReviewQueueFetchLimit`）。首屏时间
   正比于队列长度，而不是「一张卡」。
3. **最白给的一段是 ability 冷启动**：`open()` 要等卡片数据 ready 之后才由
   `OfficialAnkiReviewerStage.didChangeDependencies` 发起。ability 拉起 + 窗口
   创建 + 8 个 shell 资产预读 + Web 首导航，全都应该在用户点复习的那一刻开始。
4. **与安卓的评分档位硬差异，已于 2026-10-18 按「对齐安卓」定案并施工**：
   安卓是二档（忘记 / 记住，`BinaryRecallBar`），鸿蒙原来是四档
   （重来 / 困难 / 良好 / 简单）。现在鸿蒙也出二档，发 `again` / `good`，
   与安卓的落库语义逐字等价。详见 §5.1，**真机复验收据待取**。
5. **一处真实缺陷，已修（2026-10-18）**：鸿蒙分支的 Flutter 错误态原本没有返回
   出口（`OfficialAnkiReviewerStage._buildOhos` 的 error 分支只给「重试」，
   `OfficialAnkiReviewerErrorView` 全屏，无 back），ability 起不来时用户只能靠
   系统手势脱身。现两分支均带 `onBack`，兜底 `maybePop`，见 §3.1；**真机复验
   判据待取**。

## 1. 现状时序（代码级，逐段可核）

> **这是 2026-10-18 上午施工前的快照，不要当现况读。** 当日施工后：#3 已改为
> 首屏窗口 8 张（P0-2）、#6 已提前到用户点复习即预热（P0-1）、#8 已改单次 IO +
> 4 路有界并发（P1-3）、#9 已加暖帧（P1-4）；#2/#4/#5/#7 未变。快照保留是为了
> 让「为什么这么改」可回溯。

点击复习 → 首卡可读，实际经过：

| # | 阶段 | 代码落点 | 代价构成 | 阻塞首屏 |
|---|---|---|---|---|
| 1 | Flutter 首帧 | `AnkiReviewSessionPage.initState` → postFrame `_start()` | 一帧 | — |
| 2 | 作用域与来源解析 | `enterStudyScope` / `FormalReviewSourceCoordinator` | 轻 | ✅ |
| 3 | **批次装载** | `OfficialFormalReviewProductionLoader.load` | `listDeckTree` → **`openDeck(deckId)`（生产源带 deckId）** 或 **`openDueDeck` 逐 deck `setCurrentDeck` + `getReviewQueue(1)` 探测（仅无 deckId 的路由源 / Review All）** → `getReviewQueue(limit)` → **串行 `renderCard` × N** | ✅ |
| 4 | 会话装配 | `assembleOfficialBatch` + `restrictAllowedCards` | 轻（纯内存） | ✅ |
| 5 | 渲染器就绪 | `OfficialTemplateWebViewBody._boot` → `fromWorker()` + `adoptRenderedCard` | worker session 复用；P5 已省掉第二次渲染 | ✅ |
| 6 | **ability 冷启动** | `Stage.didChangeDependencies` → `_startOhos` → `open()` | `startAbilityForResult` + `windowStage` + `loadContent` + ArkUI 首帧 + 系统转场 | ✅ |
| 7 | shell 就绪 | `AnkiReviewerPage.bootWhenSessionArrives` → `session.start` → `preloadSync` + `preload`（MathJax 2.27 MB）→ Web 首导航 → `onPageEnd` → `markShellReady` → `waitUntilReady` | 8 个资产预读 + 内核导航 | ✅ |
| 8 | 媒体推送 | `presentCard` → `pushMediaForCard` | **串行**每文件：`length()` + `readAsBytes()` + base64（≥64 KB 走 isolate）+ 一次 channel 往返 | ✅ |
| 9 | present | `AnkiReviewerSession.present` → `runJavaScript('OfficialReviewer.present(...)')` → `replaceFrame()` 新建 iframe → `frameReady` → `setCard` → `cardAccepted` → `showQuestion` → `renderComplete` | iframe 冷加载 + `card-frame.js` 解析 + 可能的 MathJax | ✅ |

**串行化的浪费点**：

- **#6 与 #3 无依赖，却排在第 6 位。** 用户在 #3 期间只看到
  `_PreparingPanel`（居中转圈 + 「准备中」）。
- **#8 与 #7 无依赖，却排在 #7 之后。** 媒体推送要等 shell 就绪才开始。
- **#3 与 #9 的粒度都不对**：#3 渲染的是「队列」而不是「一张卡」；#8 是
  「逐文件」而不是「一批文件」。

## 2. 质量评估：能跑的 / 有缺陷的

### 2.1 已成立（有真机收据，不重复举证）

渲染、翻卡 ack、评分落库、队列真实前进、强杀冷启动恢复——见 34 收据与
ADR 0050 §3.7。2026-10-16 的评分回执、按钮互斥、末卡完成行、返回语义、
三批流畅度与产品化 UI 均已代码落库。2026-10-17 的 R0/R1、五项功能对等性、
O1 媒体分层、R2 拆分、T1 跨语言测试已施工且 hap 构建转绿；2026-10-18 的
二档对齐已施工。这些批次与 10-16 一样**只有本地门禁，真机复验收据待取**
（10-18 当日共八批：二档对齐、入口三项 D1/P1-3/P1-4、P0-1 预热、P0-2 窗口、
D8 工具栏、D9 退出确认、UI-8 回执兜底、生命周期幂等）。

### 2.2 本次审查新增的缺陷

| # | 缺陷 | 落点 | 影响 |
|---|---|---|---|
| D1 | ~~**鸿蒙错误态无返回出口**~~ **已施工（2026-10-18）** | 原：`official_anki_reviewer_stage.dart` `_buildOhos` 的 `_ohosError != null` 分支；`OfficialAnkiReviewerErrorView` 未传 `onBack` | 现：两分支均带 `onBack: _ohosBack`（兜底 `maybePop`），`!allowJs` 分支保持无 `onRetry`；真机复验收据待取 |
| D2 | **整批渲染阻塞首屏** | `official_formal_review_production_loader.dart` 的 `for (final card in queue.cards)` | 首屏时间 ∝ 队列长度 |
| D3 | **ability 冷启动未预热** | `official_anki_reviewer_stage.dart` `didChangeDependencies` → `_startOhos` | 白白串行几百 ms 到 1 s+ |
| D4 | **媒体串行推送 + 重复 IO** | `official_anki_reviewer_channel.dart` `pushMediaForCard` / `pushMedia` | N 个媒体 = N 次串行往返 + 2N 次 IO |
| D5 | **首卡 iframe 冷加载** | `assets/anki_reviewer/reviewer.js` `presentOnce` 的 `replaceFrame()` | 首卡多付一次 iframe + `card-frame.js` 加载 |
| D6 | **换卡 rebuild 仍是全队列渲染** | `official_formal_review_coordinator.dart` `_doRebuild` 的 `for (final card in queue.cards)` | 即使首屏分批，第 9 张起仍会一次性卡住（所以 D2 的分批必须同时改这里） |
| D7 | ~~评分档位两平台不一致~~ **已施工（2026-10-18）** | 安卓 `BinaryRecallBar`（2 档）vs 鸿蒙原四档 | 鸿蒙改二档，同语义；真机复验收据待取 |
| D8 | ~~鸿蒙缺 bury / suspend / redo~~ **已施工（2026-10-18）** | 原：`_AnkiStudySessionView` 的鸿蒙分支直接 `Scaffold(body: _cardSurface)`，工具栏整体省略 | 原生补三键 + `requestCardAction` 协议；真机复验收据待取 |
| D9 | ~~返回确认缺剩余张数~~ **文案已对齐（2026-10-18）** | 安卓 `AlertDialog` + `reviewExitConfirmBody(remaining)`；鸿蒙两步按键 + `EXIT_CONFIRM_WINDOW_MS` | 形态仍不同（一步弹窗 vs 两步按键），信息量已一致：都报剩余张数 |

> D1、D8 是**产品缺陷**，不是性能问题，所以它们按「各自独立一批」排期，
> 不与性能项合批。两条均已于 2026-10-18 施工。

### 2.3 本轮文档边界

本文初稿（2026-10-18 上午）**只写审查与设计，零施工**。当日下午到深夜的施工
批次已把 §3.1 / §3.2 / §3.3 / §3.4 / §3.5 / §3.8 与 §5.2–§5.4 全部落地，
各节顶部「状态」行已改为施工后实况。

**仍未施工的只剩两类**：§3.6 / §3.7（P2-5 / P2-6，只到测量方案，测完再决策），
以及 §5 表末尾 2026-10-18 审计登记的**四项形态差异**（Review All 源徽章、
高对比度主题、完成两段式、工具栏启用判定）。

无论施工与否，34 收据的 Held 项不变；也不得据此写
「鸿蒙支持 Official Anki」（AGENTS §7.1 禁语）。

## 3. 实施设计（P0/P1）

> §3 每一项的**设计**部分保持原样，但施工状态已在各小节顶部「状态」行标注：
> §3.1 / §3.2 / §3.3 / §3.4 / §3.5 / §3.8 **已施工（2026-10-18）**；
> §3.6 / §3.7 只到测量方案，未施工。任何一项落地前，34 收据的 Held 项不变。

### 3.0 统一模板与两个待拍板取舍

每项固定写八个子项，缺项视为没写完：

| 子项 | 内容 |
|---|---|
| **状态** | 设计完成 / 可施工 / 待测量；本轮全部标「不施工」 |
| **现状** | 文件 + 函数 + 当前形状 |
| **改法** | 文件 → 函数 → 改成什么形状；伪代码 ≤10 行 |
| **数据流** | 改动前后的调用顺序 |
| **关键约束** | 必须同时改的点、不能破的不变量 |
| **测试点** | 测试文件 + 断言的不变量 |
| **风险与回退** | 风险等级 + 回退方式 |
| **真机判据** | 可观测指标 + 采证方式 |

**两个待拍板取舍**（不阻塞文档，施工前必须定）：

1. **P0-1 依赖 `closeReviewer` 协议新增**——**已定：接受**（2026-10-18）。协议
   两侧各加一个方法名常量与一个 `warm_canceled` verdict；ArkTS 侧在 session 建好
   之前收到取消会记住请求（`consumePendingReviewerCancel`），由页面订阅后立即兑现。
2. **P0-2 用窗口 8，不是「严格一卡先出」**——**已定并按此施工**。严格 1 张会让
   进度从 1/1 跳到 1/8，并让 batch / ledger 提前收敛；产品若坚持一卡先出，另立
   「后台填窗」阶段，不要塞进本项。

> 篇幅说明：§3 逐项按八子项展开后全文约 530 行，超出初版 430 行预算。未拆成
> 独立文档——拆开后 44 会失去「诊断 → 设计」的连续性，而本仓库 34 收据与
> ADR 0050 本就分处 470 / 750 行量级，530 行不构成可读性问题。

### 3.1 D1 鸿蒙错误态补返回出口

**状态**：**已施工（2026-10-18）**。

**现状（施工前）**：`official_anki_reviewer_stage.dart` 的 `_buildOhos` 有两个错误
分支，**形状并不相同**——`_ohosError != null` 分支有 `onRetry` 没有 `onBack`；
`!allowJs` 分支**两个回调都没有**（fail-closed 是设计：JS 开关是用户设置，重跑
同一套引导只会同样失败）。`OfficialAnkiReviewerErrorView` 的 `onBack` 同时是
「显示开关」和回调，没传就整行按钮都不渲染。

**改法**：两处都补 `onBack: _ohosBack`，其中
`VoidCallback get _ohosBack => widget.onBack ?? () => Navigator.of(context).maybePop();`。
兜底不是可选：鸿蒙正式复习经 `OfficialTemplateWebViewBody` 进入，它**不传**
`onBack`，只写 `widget.onBack` 会得到一个「按钮在、点了没反应」的界面。

**数据流**：ability 启动失败 → `_ohosError` 置位 → 错误页渲染 → 点返回 →
`onBack` 或 `maybePop`。不触碰 ability 生命周期。

**关键约束**：不自动 pop；`_ohosError` 分支保留重试；`!allowJs` 分支**保持无
重试**；错误页保持全屏语义。

**测试点（施工后实际做法）**：`_buildOhos` 由 `isHarmonyOsTarget` 门控，而官方
SDK 的 `TargetPlatform` 枚举没有 `ohos`、无 override 值可赋，**widget 测试进不去
这条分支**。故拆成两条：

- `test/views/anki_official/official_anki_reviewer_error_view_test.dart`：组件级，
  断言两个回调各自渲染并各自触发、`onBack: null` 时无按钮、`fromUi` 在
  `fatalError` 只出返回、`recoverableError` 两个都出；
- `test/views/anki_official/official_anki_reviewer_stage_ohos_error_test.dart`：
  源码守卫（沿用 `fidelity_webview_csp_guard_test.dart` 的既有做法），断言
  `_buildOhos` 两个分支都带 `onBack: _ohosBack`、fail-closed 分支无 `onRetry`、
  `_ohosError` 分支有 `onRetry`、消息键未被互换、`_ohosBack` 确实带 `??` 兜底。

**风险与回退**：低。回退为删掉两处 `onBack`。

**真机判据**：禁用 `AnkiReviewerAbility` 后进复习，错误页一次点击可退出，不依赖
系统手势。

### 3.2 P0-1 ability 预热

**状态**：**已施工（2026-10-18）**。§3.0 取舍 1 已定：**接受 `closeReviewer` 协议新增**。

**现状**：`attach()` 由 `Stage.didChangeDependencies` 在卡片数据 ready 后调用；
`_open()` 里 `transport.open()` 不 await，随后 `await waitUntilReady()`。
ability 冷启动、窗口创建、shell 预读全部排在 loader 之后。

**改法（施工后实际形状）**：

1. 新增 `OfficialAnkiOhosReviewerBinding.warmUp({mediaRoot, transport})`，返回
   `OfficialAnkiOhosReviewerWarmUp`（`ready` future + `cancel()`）。内部建 binding
   （controller / grades 可空，resolver 由 mediaRoot 推导）→ `bindOutbound`
   （未挂接时回调全 no-op）→ `transport.open(mediaRoot)` unawaited →
   `await waitUntilReady()` → `_opened = true`；**立刻占位 `_live`**，让并发的
   `attach` 或第二次 `warmUp` 加入同一个 boot。
   **`warmUp` 自身不等 `ready`**——await 它就把 boot 又放回 loader 的关键路径，
   预热的意义归零；需要串行时由 `attach` 去 await。
2. `attach()` 改为：`_live` 存在且未关闭 → `await _live._ready` 后 `rebind`，
   **不重复 open**。
3. 调用点放 `_startOfficialOwned()` 里、`loader.load()` **之前**；失败/空批次/
   异常/`dispose` 四条路径都 `cancel()`。**不放** `_start()` 最前面——那里还没有
   `mediaRoot`、也没确认 officialOwner，会预热一个注定 fail-closed 的页。
   预热还先判 `ankiForceDisableJs`，开关打开时直接不预热。
4. `_grades` 从 `final` 改可空；未挂接时 `_rate` 回 `scheduler_unavailable`，
   防止预热期误评分。
5. boot 失败时把 `_live` 清掉（`_ready` 的 `onError` 里），下一次 attach 重新 open，
   不会继承一个半启动的 binding。**2026-10-18 补**：清槽位的同时必须
   `_abandon(force: true)` 关掉这次 boot 已经拉起的 ability——否则空页留在屏上，
   下一次 attach 会在它上面再开一页（见 §5.4）。

**数据流**：

```text
改前：click → loader（engine + 全队列渲染）→ Stage → open ability → shell ready → present
改后：click → warmUp（ability + 窗口 + shell 预读/首导航） ∥ loader（engine + 窗口渲染）
             → Stage attach（复用已 open 的 binding）→ present
```

**关键约束**：

- `cancel()` 的确定出口（**已落地**）：Dart→ArkTS 新增 `closeReviewer`；ArkTS 侧
  `requestReviewerCancel()` 若此时还没有 session 就记下请求
  （`consumePendingReviewerCancel`），页面订阅 cancel 回调后立刻兑现并
  `terminateSelfWithResult('warm_canceled')`。**没有这条就不该做预热**——
  预热一个无法取消的 ability 等于把空页风险换成后台常驻页风险。
- `cancel()` 幂等；loader 非 Ready、异常、页面 `dispose` 三条路径都要调。
- 预热失败保留原始错误，Stage 仍走现有 `_ohosError` 错误态，不吞。
- `_live` 复用要排除已关闭的旧 binding；`singleton` / `onNewWant` 语义不变。
- mediaRoot 必须与 Stage 用同一 `OfficialAnkiPaths` 的 mediaFolder。

**测试点（已落 5 例）**：`official_anki_ohos_reviewer_binding_test.dart` ——
① 预热后 attach 只 open 一次（`openCalls == 1`）；② `cancel()` 调 `close()` 并把
槽位让给下一次 attach；③ 预热态评分回 `scheduler_unavailable`（不静默吞掉也不空指针）；
④ boot 失败不成为 `_live`，下一次 attach 自行 open；⑤ **boot 连 `open` 都没发出时
cancel 不发 `close`**——ArkTS 的 `cancelPending` 会被下一个复习页消费，一次「无事
可关」的 cancel 等于毒化学习者的下一次进入。协议层由
`official_anki_reviewer_protocol_guard_test.dart` 双向断言
`METHOD_CLOSE_REVIEWER ↔ methodCloseReviewer`、`VERDICT_WARM_CANCELED ↔ verdictWarmCanceled`。

> **复检修正（2026-10-18 同日夜）**：④ 原来断言「`warmUp` 抛异常」，与实现相反——
> `warmUp` **刻意不等** `ready`（等了就把 boot 放回 loader 关键路径）。测试已改成
> 断言 `warmUp` 正常返回、`warmUp.ready` 抛错；⑤ 是这次复检发现的真实缺陷，
> 修复为 `_openIssued` 守卫（`_openWarm` 在 `bindOutbound` 之后、`open` 之前
> 检查 `_closed`）。

**风险与回退**：中（协议新增 + ability 生命周期）。回退整批：删调用点 +
`warmUp` + `closeReviewer`，不留半开状态。

**真机判据**：`hilog` 打点「点击 → `AnkiReviewerPage.aboutToAppear`」耗时，
预热前/后对比；loader 失败时无残留复习页；连续两次进复习不出现第二个 ability。

### 3.3 P0-2 首屏分批与滚动窗口

**状态**：**已施工（2026-10-18）**。`officialInitialRenderWindow = 8`，定义在
`official_formal_review_coordinator.dart`（loader 已 import 该文件，反向不成立）。

**现状**：`official_formal_review_production_loader.dart` 的 `load()` 在
`for (final card in queue.cards)` 里串行渲染整个队列；`official_study_batch_assembler.dart`
对 `presentation == null` 直接 `continue`；`official_formal_review_coordinator.dart`
的 `_doRebuild()` 同样全队列补渲染；`session.restrictAllowedCards(assembledIds)`
把会话收窄到「已装配」的卡。

**改法**：

1. 新增常量 `officialInitialRenderWindow = 8`（理由见 §3.0 取舍 2）。
2. loader：把 `placementKeys` / `retiredKeys` 的计算**移到渲染之前**，先算出
   `eligible`，再**从 eligible 里取前 8 张**渲染：

   ```dart
   final window = queue.cards
       .where((c) => eligible.contains(key(c.cardId)))
       .take(officialInitialRenderWindow);
   ```

   不能从原始 `queue.cards` 取窗口——前 8 张可能全是未引入/已退役卡，
   batch 会空，被误判成 `NoDue`。
3. `restrictAllowedCards` 改成 `eligible - 首批失败`，**不能**用 `assembledIds`；
   改造后删掉 `assembledIds` 变量，防止后来的人再拿它去 restrict。三种集合的区别：

   | 集合 | 能否传给 restrict | 原因 |
   |---|---|---|
   | `target.cardIds` | ❌ | 含未引入/已退役卡，`current` 会停在无 presentation 的卡上 |
   | `assembledIds` | ❌ | 会把会话**永久**收窄到首批 |
   | `eligible - 首批失败` | ✅ | 既避开失败卡，又保留后续窗口 |

4. `_doRebuild`：从 `session.current` 起、按 eligible 顺序补渲染至窗口满。
   失败卡记 failure 但**不占窗口名额**；不调用 `restrictAllowedCards`；
   `presentations` 仍从 `_faces` 全量取（已看过的卡不会因滚出窗口而消失）。

**数据流**：

```text
queue（≤100）→ eligible → 渲染窗口 8 → assemble(8) → restrict(eligible - 失败) → 首屏 8 张
答完第 8 张 → refreshQueue（current=第 9 张）→ _doRebuild 补 current + 前瞻 8
           → assemble（_faces 全量）→ itemsSink 替换
```

**关键约束**：

- **两处必须同批改**。只改 loader 会出现「首屏 8 张，答完第 8 张后没有第 9 张」。
- 引擎渲染保持串行——`renderCard` 没有声明可重入，不要因为窗口小就并发。
- 不引入 placeholder presentation；无 presentation 的卡继续被 assembler 跳过。
- `Review All` 的源切换只能由 `queue.cards.isEmpty` / `completed` 触发，
  不能由「窗口未满」触发，否则跨源会提前判 NoDue。
- 窗口内非当前卡渲染失败不阻塞推进；当前卡失败仍走 `currentBlockedFailure`。

**测试点**：

- `official_formal_review_loader_hydration_test.dart`：100 张 eligible 时
  `render` 调用 == 8、`batch.items.length == 8`、**`allowedCardIds != 8`**
  （这条断言是防「会话被收窄」的守门）。
- `official_live_formal_review_test.dart`：连答 20 张仍前进、`allowedCardIds` 不变；
  当前卡失败回 `OfficialLiveQueueBlockedOnCurrentCard`。
- `official_review_all_coordinator_test.dart`：两源依次推进，第一源窗口答完后
  第二源正常开始。
- `official_formal_review_unrenderable_test.dart`：窗口首卡失败时 `current` 不停在
  失败卡、allowed 不含该卡、batch 仍可启动。

**风险与回退**：中高（改的是 `allowedCardIds` 语义与装配节奏）。回退必须整批
回退 loader + coordinator + 相关测试，不保留「只改一半」的中间态。

**真机判据**：队列 ≥50 张时首屏时间不再随队列长度线性增长；答过第 8 张后
第 9 张仍在；`Review All` 跨源不漏卡；失败卡仍进 `renderFailures`。

### 3.4 P1-3 媒体推送：单次 IO 与有界并发

**状态**：**部分施工（2026-10-18）**。单次 IO 与有界并发已落；「提前」**不做**，
原因见改法第 3 条。

**现状（施工前）**：`official_anki_reviewer_channel.dart` 的 `pushMedia()` 先
`await file.length()` 再 `await file.readAsBytes()`（两次 IO，且大文件会被整读进
内存再丢弃）；`pushMediaForCard()` 对 `names.toSet()` 串行 `await pushMedia(...)`，
一个名字抛异常就中断后面全部。

**改法（施工后实际形状）**：

1. **单次 IO**：`await file.open()` → `await handle.read(directReadBypassThreshold + 1)`。
   缓冲区填满（>256 KB）就是「该走 Range」的判据，**不整读**；短于阈值就是 EOF，
   无需续读。一次 open 同时回答了「多大」和「内容是什么」。
2. **有界并发 + settled 语义**：`pushMediaForCard` 改成 4 路 worker pool，返回
   `Set<String>`。集合的语义是 **settled（无需再试）**，不是「成功」：
   推送成功、resolver 拒绝（文件不存在/越界）、超阈值走直读——三者都算 settled，
   因为重试不可能改变结果；只有**读盘或通道抛异常**才留在集合外，下次 present
   重推。若按「成功」记账，一张带 3 MB 音频的卡会**每次 present 都重读它的前
   256 KB**，那是把优化做成回归。
3. ~~**提前**：`_open()` 里把 prefetch 与 `waitUntilReady()` 并行~~ **不做**。
   `open()` 返回的是「用户关闭 ability 的 verdict」，不是「会话已建立」，
   `cacheReviewerMedia` 在 session 建立前回 `REVIEWER_NOT_OPEN`。没有 P0-1 预热时
   `open` 与卡片 ready 几乎同时发生，把 prefetch 塞进这段窗口要么加重试、要么
   与 `presentCard` 串行——**并行窗口≈0**。等 P0-1 落地（open 提前到点击时刻）
   再单独做，届时才有真实的几百毫秒可以重叠。

**数据流（当前）**：

```text
open → waitUntilReady → presentCard → [并发 4 推送 settled 的名字] → present
```

**关键约束**：

- 并发上限固定 4（`OfficialAnkiReviewerChannel.mediaPushConcurrency`），不要无界
  `Future.wait`：每个 worker 持有一个文件的字节 + 其 base64，而卡可以引用十几个图标。
- `> 256 KB` 的直读绕行逻辑不动；`read(threshold+1)` 已经避免把大文件读进来。
- `_pushedMediaNames` / `_pushedMediaCardId` 的换卡清空语义不动。
- 单个媒体推送失败不应让 present 失败：origin server 对未缓存的小文件仍走磁盘读，
  最坏是 500 `MEDIA_READ_FAILED`，不是「卡片打不开」。
- 若将来做「提前」，对 `REVIEWER_NOT_OPEN` 做有界重试（20 × 25 ms），
  不做无界等待；更干净的 `awaitReviewerSession` 轻量方法留到后续协议批次。

**测试点（已落）**：`official_anki_ohos_reviewer_binding_test.dart` ——
① 8 个媒体时 channel 层 in-flight 峰值 `<= mediaPushConcurrency`（只断言上界：
是否真正重叠取决于测试 messenger 的调度，不是本项要钉的不变量）；
② fake transport 制造一个「未 settled」的名字，断言它下次 present 被重推、已
settled 的名字不重推；③ 既有 O1 用例继续断言 `> 256 KB` 不产生 base64 调用。

**风险与回退**：低。回退：并发改回串行、`read(threshold+1)` 改回
`length()+readAsBytes()`；两处可独立回退。

**真机判据**：含 ≥5 个媒体的卡首卡时间；同一文件不重复推（`_pushedMediaNames`
命中）；大媒体仍走原生 Range 直读，不出现 base64 峰值。

**真机判据**：含 ≥5 个媒体的卡首卡时间；同一文件不重复推（`_pushedMediaNames`
命中）；大媒体仍走原生 Range 直读，不出现 base64 峰值。

### 3.5 P1-4 首帧 iframe 预热

**状态**：**已施工（2026-10-18）**。

**现状**：`assets/anki_reviewer/reviewer.js` 的 `presentOnce()` 里
`var newCard = !frame || incomingCardId !== lastFrameCardId`，首卡必然
`!frame`，因此一定 `replaceFrame()`，多付一次 iframe + `card-frame.js` 冷加载。

**改法**：

1. 新增 `warmFrame()`（幂等），挂到 `window.OfficialReviewer`；`clearCard()`
   里复位暖帧标记。
2. `ensureFrame` 改为**不毁暖帧**：`frame && frameWarm` 时等 `frameReady`，
   超时才 `replaceFrame()`。
3. `presentOnce` 的 newCard 判定改用 `hasPresented`（首次成功 `setCard` 后置
   true），**不用 `lastFrameCardId = -1` 当哨兵**——哨兵会被误判为「换卡」。
4. ArkTS：`AnkiReviewerSession.markShellReady()` 末尾
   `runJavaScript('…warmFrame()')`，失败静默；**不在 `present()` 里调用**，
   暖帧必须早于第一张卡。

**数据流**：

```text
改前：shell ready → present（首卡）→ replaceFrame（新建 iframe）→ 等 frameReady → setCard → renderComplete
改后：shell ready → warmFrame（预建 iframe）→ present（首卡）→ ensureFrame 命中暖帧 → setCard → renderComplete
```

**关键约束**：暖帧不得设 `lastFrameCardId`；不得在暖帧阶段发 `setCard`
（会提前触发 `cardAccepted`，扰乱 generation）；`setCard` 已有的
`host.innerHTML = ""` 保留，负责清残留；旧 shell 没有 `warmFrame` 时
present 必须仍走原路径（`&&` 短路即可）。

**测试点（已落）**：`test/application/anki_official/js/card_frame_protocol_test.mjs`
新增 4 例 —— 两次 `warmFrame()` 只建一个 frame；暖帧后首次 present 不建第二个
frame；暖帧 `frameReady` 永不就绪时回退 `replaceFrame()` 且 present 仍成功；
`clearCard()` 后可再暖。既有 7 例都不调 `warmFrame`，等于持续覆盖「旧 shell /
未预热」路径。

> **清单同步是硬要求**：`assets/anki_reviewer/manifest.json` 逐文件校验 sha256，
> 改 `reviewer.js` 必须同步 `sha256` 与 `bytes`，否则
> `official_anki_reviewer_assets_test.dart` 必挂。施工时发现该条目本就已经与
> 工作树文件不一致（上一批改过 `reviewer.js` 但未同步清单，属既有漂移），
> 本次一并订正。

**风险与回退**：低–中（风险在 `ensureFrame` 的超时分支）。回退：删 `warmFrame`
调用并把 `newCard` 判定改回原状。

**真机判据**：首卡 `present` → `renderComplete` 的 ack 时间（现有约 60 ms 是
**翻卡**，首卡必须单独量）；首卡只创建一个 iframe（debug chrome 计数）。

### 3.6 P2-5 队列探测：本轮只写测量方案，不施工

**状态**：待测量，**不施工**。

**现状**：`official_anki_review_session.dart` 的 `openDueDeck()` 对每个 deck 做
`setCurrentDeck` + `getReviewQueue(fetchLimit: 1)` 探测，按 `new + learning +
review` 选最大。

**为什么原方案不成立**（上一版写的「用 deck tree 计数直接选 deck」已否决）：

- `OfficialAnkiDeckNode` 确实有 `newCount` / `learnCount` / `reviewCount` /
  `dueCount`（已核实），但它是**全局**计数，不是 `allowedCardIds` 过滤后的。
  `openDueDeck` 恰恰用于无 deckId 的路由源 / Review All，全局 due > 0 的 deck
  可能没有任何本源的 allowed 卡。
- 现有逻辑是「比较所有 deck 的探测计数后选最大」。用 tree 计数替代会
  **改变 deck 选择结果**，不只是省往返。
- 生产 loader 在 `target.deckId >= 0` 时走 `openDeck`，根本不进这个函数，
  覆盖面比原方案暗示的小得多。

**只保留安全子集**：`if (deck.dueCount == 0) continue;`（全局 0 due ⇒ allowed
必然 0，跳过安全），并保留其余 deck 的 `getReviewQueue(1)` 探测以维持选择语义。
先加计数器测「探测 deck 数 / 因 0 due 跳过数 / 探测总耗时」，占比确实高才动。

**真机判据**：多 deck 源的进入复习耗时；选中 deck 与改动前一致。

### 3.7 P2-6 present payload：本轮只写测量方案，不改传输

**状态**：待测量，**不施工**。

**现状**：`AnkiReviewerSession.present` 把整段 JSON 拼进
`runJavaScript('window.OfficialReviewer.present(' + payloadJson + ', …)')`，
大卡 HTML 全文跨 WebView eval；目前没有体积与耗时数据。

**为什么不改**：`runJavaScript` 的解析成本在内核，未测量前无法判断它是不是
首卡瓶颈；改成 origin server fetch + 异步 ack 会引入新的时序、缓存与失败路径，
风险远大于潜在收益。

**测量设计**：JS 侧记录 `payloadBytes = JSON.stringify(payload).length` 与
`presentMs`（present 开始到 terminal ack）；ArkTS 侧记录 `payloadJson.length` 与
`evalMs`。仅在 `payload.debug == true` 时写进 ack；**只记长度与时长，不记 HTML**。

**进入决策的门槛**：采样 ≥20 张首卡，且同时满足
`p95 payloadBytes > 256 KB` **与** `p95 evalMs > 50 ms`（或 eval 占首卡 >10%）。
否则结案为「非瓶颈」，从施工清单里删掉。

### 3.8 D8 工具栏：redo / bury / suspend（本轮施工）

**状态**：已施工（2026-10-18）。

**现状（改前）**：安卓 `_AnkiSessionToolbar` 有三个 `IconButton`
（`redo_rounded` / `bedtime_outlined` / `pause_circle_outline_rounded`）；
鸿蒙分支 `if (isHarmonyOsTarget) return Scaffold(body: _cardSurface(...))`
把整个工具栏跳过了。鸿蒙只有 `撤销`（`AnkiReviewerHeaderBar` 里的文本按钮）。

**改法**：

1. **协议**：新增一个出向方法 `requestCardAction` + 动作词
   `redo` / `bury` / `suspend`，两侧常量同名同值，由既有守卫的标量对称
   断言自动覆盖。**一个方法而不是三个**：三者共享同一条回执契约和同一组前置
   条件，三个方法就是一个 switch 的三份副本、三次漂移机会。
2. **回执复用既有词表，不新增**：`advanced → ok`、`completed → ok_complete`、
   `refused → scheduler_unavailable`、宿主抛异常 → `engine_error`。理由是
   守卫里有一句「回执码是十个互异值」的断言——为三个状态再造两个词，等于在
   两侧各加两个分支来描述已经能表达的东西。
3. **宿主**：`_AnkiStudySessionView` 的三个钩子照抄安卓
   `onRedo`/`onBury`/`onSuspend` 的序列（mutate → `rebuildFromLiveQueue` →
   `advanceFromScheduler`），抽到 `advanceAfterNativeMutation`。返回
   `OfficialNativeMutation` 三态而不是 `bool`——`bool` 会让「完成」与「被拒」
   无法区分，而一次被拒的搁置若被当成完成，就会在队列还有卡时结束会话。
4. **UI**：`AnkiReviewerHeaderBar` 加第二行（右对齐三个文本键），位置对齐安卓
   的工具栏（卡片上方的横条）；`撤销` 仍留在计数行，因为安卓的
   `ReviewProgressHeader` 也在那里——这个分工是刻意的。预览态整行隐藏
   （预览没有可变更的会话，回执会全是「不可用」）。
5. **互斥**：`mutating` 与 `ratingSent` 一样是页面级互锁。两者都改同一个
   调度器，放行共存等于让两次推进赛跑一次队列。三个顶栏入口的 `enabled`
   显式读 `!ratingSent`（2026-10-18 补记）；`ratingSent` 的解除点是「下一张
   问题面落地」（`presentPending=false && answerLanded=false`），不是回执本身
   ——回执一到就解除会让同一张卡被评两次。

**数据流**：

```text
ArkUI 按钮 → page.requestCardAction(word) → bridge（带回执接收器）
  → channel（Dart）→ binding._cardAction(word)
  → 宿主钩子：redoLast / buryCurrent / suspendCurrent → rebuild → advance
  → 三态 → ok / ok_complete / scheduler_unavailable → 页面回收互锁或收尾
```

**关键约束**：

- `redo` 走 `controller.redoLast()`，**不是** `session.redo()`：后者只动引擎，
  不动控制器的 `_undoneReceipt`，重做之后批次与位置会对不上。
- 三项都必须带 `onMutated: liveQueue.rebuildFromLiveQueue`，否则搁置/暂停后
  队列仍是旧的，棋盘上还挂着已被移出队列的卡。
- 未知动作词**只回执、不派发**：新 shell 发来一个 Dart 不认识的词是协议漂移，
  不是用户操作，它不能有机会改动队列。
- `_cardAction` 在预热态（`_onRedo == null`）必须回 `scheduler_unavailable`，
  与评分路径的 `_grades == null` 分支同构。

**测试点**：

- `official_anki_ohos_reviewer_binding_test.dart` 新增 7 例：三个动作词各达
  自己的钩子；`completed → ok_complete`；`refused → scheduler_unavailable`；
  未知词不派发；宿主抛异常回 `engine_error`；预览态不触钩子；预热态回
  `scheduler_unavailable`。
- `ohos_card_action_chrome_guard_test.dart`（新）：chrome 三键存在且各自回调
  自己的钩子、整行在 `!previewOnly` 内、三键共用一条 `enabled` 规则、页面用
  协议常量而非字符串字面量、回执路径含 `ok_complete`/`complete`/`settlement`、
  桥原样转发动作词且带回调。
- 协议守卫：`requestCardAction` 与三个动作词由既有标量对称断言覆盖，无需改。

**风险与回退**：中低。回退：删掉 chrome 第二行即可让三个入口消失，协议与
binding 留着不产生调用；再退一步删 `requestCardAction` 三处常量，守卫会
同时红，正好挡住半删。

**真机判据**：见 §6 的 D8 行——搁置/暂停在浏览器与调度器两侧都生效（队列计数
下降、卡不再出现），重做恢复上一张且计数回退，三者在预览态不可见。

## 4. 减少打扰

### 4.1 原则

鸿蒙的「跳转」本质是一次 ability 页面替换，**无法消除**，但可以让它
**看起来不是跳转**。四条产品原则，具体改法一律见 §3：

1. **预热进页**——把等待从「跳转前」搬到「跳转后」（§3.2）。
2. **首帧视觉连续**——Flutter `Scaffold` 背景与 ArkUI `palette().bg` 对齐
   （day `#F4F7F7` / night `#10181B` 对 `TurnaTheme.scaffoldBg`），
   系统转场期间不闪色。
3. **首屏给卡片骨架，不给空气**——ArkUI 无卡片时是一个空 surface 圆角块
   （`Web` 的 `backgroundColor(palette().surface)`），应换成与卡片同内边距、
   同圆角的骨架。
4. **错误态要有出口**——见 §3.1，这是缺陷而非优化。

### 4.2 转场

ArkUI ability 拉起走系统默认转场。可评估
`windowStage.getMainWindowSync().setWindowTransitionAnimation(...)`（API 26
可用性需核对）改为淡入，避免「缩放跳页」观感。**不阻塞前四条**。

### 4.3 状态文案

- ~~鸿蒙两步返回确认的文案未带剩余张数，安卓的 `reviewExitConfirmBody(remaining)`
  带。建议对齐。~~ **已施工（2026-10-18）**：文案改为
  「还剩 N 张未完成，再按一次返回或 ✕ 结束复习（已评分的卡片会保留）」，
  计数口径与安卓 `ReviewSessionController.remainingCount` 一致（
  `items.length - currentIndex`，含当前这张）；N 未知时回落原文案。
- ArkUI 状态区的 `正在加载…` / `调度器忙，请再点一次` 与 Flutter 的
  `AppStrings` 是两套硬编码中文（`AnkiReviewerPage.ets` / `AnkiReviewerChrome.ets`）。
  当前没有 l10n 需求就不动，但要记在案：**这是未来的口径漂移点**。

## 5. 与安卓对齐

| 维度 | 安卓 | 鸿蒙 | 判定 |
|---|---|---|---|
| 评分档位 | 2 档（忘记 / 记住）`BinaryRecallBar` | 2 档（忘记 / 记住）原生底栏 | ✅ 2026-10-18 对齐 |
| **评分后推进** | `submitRecall` 内部连推进 | `advanceFromNativeRating` → `advanceTo(调度器 current)` | ❌ **真机缺陷（2026-10-18 夜）**：评分已落库，推进抛 `advance_failed`；批次长度 2 而调度器 current 是另一张 → 更可能是 `advanceTo` 因 `phase != readyForNext` / `_locked` 静默 no-op，报错文案却只写「不在批次」。已在失败分支加结构化日志，根因待复现 |
| 评分落库路径 | `submitRecall` → `OfficialStudyLedger.commit` | `_rate` → `answerOfficialCard` → `advanceFromNativeRating` | ✅ 同源不同入口 |
| 语义折叠 | `RecallOutcome` 二态（`submitRecall` 入口即二态） | again/hard→forgotten，good/easy→remembered | ✅ 两路等价：鸿蒙只发 again/good，折叠后经 `OfficialAnkiReviewLedger` 又发回 `again`/`good`，与安卓落库值逐字相同（2026-10-18 核对） |
| 卡片渲染 | WebView + 同款 shell | ArkUI `Web` + 同款 shell | ✅ |
| 翻面 | 「显示答案」按钮 | 原生底栏 / 输入框回车 | ✅ |
| 音频重播 | Flutter 图标 | 原生「重播」+ avHint | ✅（对等性已补） |
| 撤销 | Flutter 顶栏 | 原生顶栏 | ✅ |
| 进度口径 | `currentIndex+1 / totalCount`（`totalCount => items.length`） | `answeredCount+1 / (answeredCount+items.length)` | ✅ 正常路径数值一致（`currentIndex` 由 `advanceTo` 按调度器 current 设定、与 `answeredCount` 同步）；队列收缩时安卓分母跟着缩、会读出「3/2」，鸿蒙用「已答+剩余」不会——**差异方向是鸿蒙更稳，不是鸿蒙落后**（2026-10-18 订正） |
| 返回确认 | AlertDialog（带剩余张数） | 两步按键 + 2 s 窗口（**2026-10-18 起也带剩余张数**） | ⚠️ 形态不同，信息量已一致 |
| 完成 | Flutter `UnifiedReviewCompletion` | 单源：原生行只做 0.6 s 收尾（「复习完成 / 正在打开结算…」，无统计无按钮）→ 自动关 → 落回**同一个** `UnifiedReviewCompletion`；Review All：保留「完成」按钮（下一源要复用同一个 ability，只能由 Dart 决定何时关），点后同样落到该组件 | ✅ 2026-10-18 施工（UI-16） |
| 工具栏 | redo / bury / suspend | redo / bury / suspend（顶栏第二行） | ✅ 2026-10-18 对齐 |
| 工具栏启用判定 | redo 看 `controller.canRedo`；bury/suspend 看 `canMutate` | payload 下发 `canRedo` / `canMutate`，三键在共享互锁前缀后各自追加自己的谓词 | ✅ 2026-10-18 施工（UI-15） |
| Review All 源进度 | `_AnkiSessionToolbar` 左侧「3/5 · Deck 名」徽章 | payload 新增 `sourceProgress`（与安卓同一字符串），原生顶栏第二行左侧渲染徽章，空串时不渲染 | ✅ 2026-10-18 施工（UI-15） |
| 主题档位 | 四套：light / dark / highContrastLight / highContrastDark | payload 新增 `chromeTheme` 四值；`theme` 仍只给卡片 frame 用 day/night；ArkTS 增两套高对比色板 | ✅ 2026-10-18 施工（UI-15） |
| 错误出口 | 页内错误 + 返回 | 两分支均带 `onBack`（兜底 `maybePop`） | ✅ 2026-10-18 修复（原为 ❌ D1），真机判据待取 |

### 5.1 评分档位：**已定案「对齐安卓」（二档），2026-10-18 施工**

方向反转记录：本文初稿推荐「安卓改四档」（四档是 Anki 官方语义，鸿蒙已做完
产品化）。负责人 2026-10-18 拍定 **以安卓为基准，鸿蒙改二档**。理由记录在案，
避免后来的人把这次改动当成退化：

- **一致的交互 > 更细的调度粒度**。同一张卡在手机与平板上出现两种选择数，
  是可感知的产品不一致；而 `hard`/`easy` 的调度差异在二档用户眼里本来就不可见。
- **安卓是当前的主交付平台**（首发 Android arm64 + iOS，鸿蒙伴生版不进主交付，
  ADR 0047 / 0051 语境）。基准放在主交付平台上，改动成本只落在伴生版一侧。
- **等价性是可证的，不是近似的**：`OfficialAnkiReviewLedger` 对二态 outcome
  发出的 rating 就是 `forgotten → again`、`remembered → good`
  （`official_anki_review_ledger.dart`）。鸿蒙只要发这两个词，落库与调度结果
  与安卓逐字一致，不需要任何映射层。

**施工落点**（2026-10-18，四个文件）：

| 文件 | 改动 |
|---|---|
| `ohos/.../anki/AnkiReviewerChrome.ets` | 删除 `RATINGS` 四档清单；评分行改为显式两个按钮（`ratingLabel(RATING_AGAIN)` / `(RATING_GOOD)`），12% 填充 + 35% 同色描边 + 圆角 16 + 高 52，镜像安卓 `_RecallButton`；新增 `COLOR_AGAIN_TINT/_EDGE`、`COLOR_GOOD_TINT/_EDGE` 四个 ARGB 常量；`ratingLabel` 的 again/good 文案改「忘记」「记住」；`ratingSent` 行高度 52 与评分行齐平，切换不跳 |
| `ohos/.../pages/AnkiReviewerPage.ets` | 文件头注释：four rating buttons → two |
| `ohos/.../anki/AnkiReviewerProtocol.ets` | 注释去掉数量词（**四个 rating 词仍全保留**，engine 说四个） |
| `lib/.../render/official_anki_reviewer_protocol.dart` | 同上，两处注释去数量词 |

**刻意没做的事**：

- **协议层不删 `hard` / `easy`**。engine 与 `answerCard` 仍接受四个 rating，
  Dart 侧 `advanceFromNativeRating` 的折叠规则（again/hard→forgotten、
  good/easy→remembered）原样保留。删词会让协议守卫测试与引擎契约同时失配，
  而收益只是少两个常量。
- **`ratingColor()` 保留**。两档底栏不再调用它（改用显式 tint/edge 对），
  但它仍是「四个 rating 词 → 四个品牌色」的唯一映射，四档表面若回归会直接需要它。
- **`已提交，加载中…` 提交态保留**。安卓是按钮置灰、鸿蒙是单按钮换行；语义一致，
  原生形态更防重复点击，不在本次对齐范围内。

**真机复验收据待取**：ArkTS 侧无本地类型检查（`deveco check` 余留诊断为 LSP
环境项，与既有批次相同），hap 未重编，真机未跑。**这一条在真机过卡前不算完成**——
验收判据见 §6 的 D7 行。

**代价与已否决备选**：安卓侧**零改动**，成本只在鸿蒙伴生版；鸿蒙失去 `hard` /
`easy` 两档的调度粒度（该粒度在二档交互下本就不可见），四档产品化 UI 收敛为
二档。初稿曾建议「安卓改四档」，已由 2026-10-18 定案否决——那会把一次纯 UI
对齐扩大成引擎语义与统计口径的改动，且与主交付平台的既有交互冲突。协议层四词
保留，未来若恢复四档不需要动协议。

### 5.2 工具栏（D8）——已施工（2026-10-18）

鸿蒙分支原缺 redo / bury / suspend：这三项在安卓是 `_AnkiSessionToolbar`
里的三个 `IconButton`，而鸿蒙分支整个 `Scaffold` 省略了它。

**两条路都评估过**：原生补（ArkUI 顶栏加入口，走 channel）或 Flutter 补
（鸿蒙分支保留一个极简 Flutter 顶栏）。**选了原生补**——鸿蒙复习页的整套
chrome 都在 ArkUI 侧，塞一个 Flutter 顶栏等于在 Web 之上再叠一层 Flutter，
转场时会露馅，而且它与既有 `撤销` 入口的形态会不一致。

**产品口径**：三项都要。这条链路的验收目标是「与安卓对齐」，安卓三个都在，
少任何一个都还是不对齐；`bury` / `suspend` 虽是重度用户功能，但 `redo` 是
`undo` 的天然配对，单缺它会让「撤销」变成一个不可回退的动作。

施工落点与关键判断见 §3.8。

### 5.3 回执兜底与评分互斥（UI-8）——已施工（2026-10-18）

真机症状：复习页卡在「已提交，加载中…」。根因是**回执的失败面没有出口**：
`onRateReceipt` 只对 `answer_not_ready` / `scheduler_busy` 复位 `ratingSent`，
兜底分支（`session_closed` / `no_card` / `engine_error` /
`scheduler_unavailable` / `card_mismatch` / `channel_error_*` /
`bridge_detached`）与 `advance_failed` 分支只 `showError`，按钮永久禁用。

第二条链更隐蔽：`advanceFromScheduler` 在调度器 current 不在批次里时调
`reportSchedulerDesync`（phase → `recoverableError`），而
`advanceFromNativeRating` 用 `phase != readyForNext` 判「已前进」→ 回执 `ok`。
但 desync 路径 **generation 不自增**，外层 `_boot()` 不重跑，
`_scheduled` 的 `(cardId, side, presentGeneration)` 三元组不变 → present 永不
发出 → 页面等一张不会来的卡。

**三条硬结论**：

1. `ok` 与 `advance_failed` **不解除** `ratingSent`：两者都代表提交已落库，
   解除等于允许同一张卡二次提交。解除点是「下一张问题面落地」
   （`!presentPending && !answerLanded`）。
2. 推进失败**抛 `StateError`**，不返回 `false`：后者会被
   `_runAdvance` 翻成 `ok_complete`，在调度器还欠卡时显示「复习完成」。
   抛错落在既有 `advance_failed` 上，不新增回执码。
3. desync 之后的重试必须先把 phase 拨回 `readyForNext`
   （`acceptExternalOfficialCommit` 的幂等重放分支），否则重试是永久
   no-op（`advanceTo` 只接受 `readyForNext`）。

兜底看门狗 20s：覆盖引擎提交 + 推进（P0-2 窗口最多补渲染 8 张）+ 媒体推送
+ present 自身的 12s ack 超时。到期转 `advanceStuck` 的重试/结束行。

### 5.4 reviewer 生命周期幂等——已施工（2026-10-18）

真机症状：页面重复跳转。三条独立成因，都在 ability / session 生命周期上：

1. **重复 open**：`OfficialAnkiOhosReviewerBinding.attach` 在 `await _ready`
   期间不占 `_live`（`warmUp` 会占）。并发 attach 各建一个 binding 各发一次
   `openReviewer`；singleton ability 的第二次启动走 `onNewWant`，那里无条件
   `beginReviewerSession` + `loadContent` → **整页重载**。
2. **误关**：`_abandon()` 不看是否已被 Stage 接管。Review All 换源到 blocked
   源时 `_abandonOhosWarmUp()` 会关掉正在显示的 reviewer，页面随即
   `maybePop()`。
3. **绑旧会话**：`onNewWant` 换掉 session 后，页面 `booted` 闩锁使其无法重绑，
   listener 全留在旧对象上；`aboutToDisappear` 又按「当前」`reviewerSession()`
   清监听，可能清掉新页面的。

**修法**：

- `attach` 同步占 `_live`，boot 失败 `_abandon` 关掉已拉起的 ability。
- 新增 `_adopted`：加载器句柄的 `cancel()` 不再关已接管的 reviewer；页面离开
  走静态 `shutdown()`（`force: true`）。
- `onNewWant` 按 mediaRoot 分流：同 root + 活会话 → `noteReviewerWantDelivered`
  后直接返回（不重建、不重载）；异 root 才重建。
- epoch 从「session 世代」改为「已服务请求数」`wantEpoch`，插件在
  `startAbilityForResult` **之前**捕获 —— 否则复用路径的 `awaitReviewerReady`
  会空等 8s。
- 页面记 `boundSession`，`onPageShow` 校验重绑；`aboutToDisappear` 只解绑自己
  绑的那个；`requestCancel` 在未订阅时缓存。

## 6. 验收方式

每一条都要能在真机上给收据，不接受推断。**P2-5 / P2-6 不在本表**——它们本轮
只到「测量方案」，测量通过才进决策。

| 项 | 判据 | 采证方式 |
|---|---|---|
| D1 错误出口 | 禁用 ability 后进复习，错误页一次点击可退出 | 真机 + 注入 `open` 失败 |
| P0-1 预热 | 点击 → ArkUI 首帧耗时；装载失败无残留复习页；连进两次不出现第二个 ability | `hilog` 打点（`aboutToAppear`），预热前/后各 ≥5 次取中位 |
| P0-2 分批 | 队列 ≥50 张时首屏时间不随队列线性增长；第 9 张仍在；`Review All` 不漏卡；失败卡仍进 `renderFailures` | 真机 + debug chrome 的 render 计数 |
| P1-3 媒体 | 含 ≥5 媒体的卡首卡时间；同一文件不重复推；大媒体仍走 Range | `_pushedMediaNames` 命中日志 |
| P1-4 暖帧 | 首卡 present → `renderComplete` 的 ack 时间；首卡只创建一个 iframe | debug chrome；现有 60 ms 是**翻卡**，首卡必须单独量 |
| D7 二档 | 同卡同评级两平台落库 rating 一致（`again`/`good`）；标签与语义色一致；评分行切换不跳布局 | 真机过卡 + 两平台对拍 |
| D8 工具 | bury / suspend / redo 产生与安卓相同的调度效果 | 真机 + 调度前后队列对比 |
| D9 退出确认 | 两步确认的第一跳文案报出剩余张数，且与 `remainingCount` 同口径 | 真机 + 对照 `progressIndex/progressTotal` |
| UI-8 回执兜底 | 注入 desync（把 current 卡从批次过滤）后评分，底栏出「重试进入下一张 / 结束复习」，不停在「已提交，加载中…」；重试一次可前进 | 真机 + debug chrome 的 `errorCode` |
| 生命周期幂等 | 连续进入复习 ×20 不出现整页重载；Review All 含 blocked 源不被弹回复习外；返回只退一页 | 真机 + `hilog` 的 `reusing the live reviewer session` 计数 |

**口径提醒**：本文任何一条施工完成，都不改变 34 收据的 Held 项
（真机导入、课程学习解锁、步 6 首跑收据、互斥与三批修复的真机复验）。
不得据此写「鸿蒙支持 Official Anki」（AGENTS §7.1）。

## 7. 排期

**初稿是「本轮只完成文档，不动代码」；下表已按 2026-10-18 当日施工实况回填。**
当前只剩第 7 项与第 10 项未动。

1. ~~**D7 二档对齐**~~ **已施工（2026-10-18）**，只差真机过卡验证
2. ~~**D1 + P1-3 + P1-4**~~ **已施工（2026-10-18）**：D1 错误出口、P1-3 单次 IO +
   有界并发、P1-4 首帧暖帧。P1-3 的「提前」未做，理由见 §3.4 改法第 3 条。
   三件同批，一次真机可验
3. ~~**P0-1 预热**（依赖 `closeReviewer` 协议新增；取舍未定则不做）~~
   **已施工（2026-10-18）**：协议新增已接受，`warmUp` / `cancel` / 调用点四条
   取消路径落地。真机判据待取
4. ~~**P0-2 分批装载**~~ **已施工（2026-10-18）**：窗口 8、eligible 过滤、
   `restrictAllowedCards` 改 `eligible - 失败`、`_doRebuild` 滚动窗口。
   **行为收据已取**（同日复检）：`official_formal_review_render_window_behavior_test.dart`
   用 20 卡夹具断言 `renderCount == 8` / batch 8 张 / `allowedCardIds` 20 张，通过
5. ~~**D8 工具栏**（功能缺口，单独排期；需先确认是否三个都要）~~
   **已施工（2026-10-18）**：三项全要，原生补三键 + `requestCardAction`
   协议 + 三态回执，见 §3.8。真机判据待取
6. ~~**D9 退出确认文案**~~ **已施工（2026-10-18）**：补剩余张数，口径对齐安卓
   `remainingCount`（含当前这张），N 未知时回落原文案；见 §4.3
7. **P2-5 / P2-6**（先测量，测完再决定是否立项）——只到测量方案，未施工
8. ~~**UI-8 回执兜底与评分互斥**~~ **已施工（2026-10-18）**：见 §5.3。真机判据待取
9. ~~**reviewer 生命周期幂等**~~ **已施工（2026-10-18）**：见 §5.4。真机判据待取
10. ~~**§5 表四项形态差异**~~ **全部施工（2026-10-18）**。
    - **UI-15 三项**：Review All 源徽章 / 高对比度主题档位 / 工具栏启用判定。
      落点：`ohosReviewerPayload` 新增 `sourceProgress`/`canRedo`/`canMutate`/
      `chromeTheme`；`OfficialReviewerChromeSnapshot` 记录在页面与 binding 之间
      传递三项（主题由 Stage 算，因为只有 widget 层能读无障碍 scope）；ArkTS 侧
      `ReviewerChromeState` 同步字段，`paletteForTheme` 扩到四档，
      `AnkiReviewerHeaderBar` 加源徽章与两套谓词。
    - **UI-16 完成交棒**：原生完成行在单源会话下只做 600 ms 收尾即自动关闭，
      让位给底下已经渲染好的 `UnifiedReviewCompletion`（安卓那张）。
      **此前文档把这一项写成「两个完成屏」是错的**——真实形态是一个都不完整：
      `_onNativeAbilityClosed` 无条件 pop，把底下那张完成屏直接弹掉了。所以这一项
      不是"合并两屏"，而是"让那张一直没被看到的屏留下来"，顺带修掉
      「完成态跳过结算导致 XP 恒为 0」。
    - **ArkTS 编译器收据已取**（2026-10-18，build hap 成功，见 34 收据同节）。
