# Anki 复习统一施工计划

> 状态：核心生产路径已实施；官方历史聚合与官方管理仓库留作后续切片
>
> 日期：2026-08-20
>
> 范围：Anki 复习页、课程内 Anki、今日重点、通用 SRS、历史记录、统计与撤销
>
> 目标：先消除数据错误和多套语义，再统一为课程式复习体验；本文同时记录施工结果与未完成边界。

## 0. 结论先行

现在的问题不是“三个页面长得不一样”，而是同一批卡片同时落在多套入口、评分口径、调度账本和统计口径里。当前至少存在：

- 6 类可见复习入口；
- 4 套评分/熟练度语义；
- 2 个正式调度账本，外加 1 条误入通用 SRS 的旁路；
- 2 套撤销责任；
- 3 套完成、奖励和错题副作用；
- 多份互相冲突、仍被测试固化的设计文档。

施工后的产品合同必须收敛成一句话：

```text
所有入口
  -> 同一套“课程式复习会话”
  -> 用户只回答：不记得 / 记得
  -> 根据卡片来源选择唯一账本写入
       Turna / 旧导入：Again / Good -> Turna FSRS
       官方 Anki：    Again / Good -> 官方 Anki Scheduler
  -> 预览、历史、撤销、统计都从实际写入的账本返回
```

这里统一的是产品语义和交互，不是强行让两套调度器算出相同的间隔。官方 Anki 仍以官方调度器为事实来源；Turna 内容仍由 Turna FSRS 调度。界面不得自行猜测“下次复习时间”。

### 0.1 本轮施工结果（2026-08-20）

已进入生产路径：

- `SrsReviewPage` 与旧导入 `AnkiReviewSessionPage` 使用
  `UnifiedReviewPage + ReviewSessionController`；旧导入不再制造临时
  `Lesson`，也不再借用 `LessonViewModel` 负责正式复习。
- 官方正式复习保留官方 presenter/WebView 与 answer-present ACK 安全协议，
  但外壳、进度、完成页和二元按钮与课程式复习统一；`Hard/Easy` 不再可见。
- 课程里的官方 Anki 投影明确为练习态，不写 Turna SRS，也不暗改官方排期。
- Turna 与官方 ledger 都只接受 `forgotten/remembered`；正式写入分别映射到
  Turna fail/pass 与官方 Again/Good。官方 ledger 只有在 scheduler 返回已提交且
  card ID 一致时才产生 receipt。
- Turna failure preview 使用当天真实失败历史；撤销通过 receipt 的唯一
  `sourceKey` 删除精确历史事件，并恢复对应 SRS 快照。旧 Anki 每日配额与错题
  也随撤销补偿。
- 官方到期数改为单次 deck-tree 快照，包含 new/learning/review，独立牌组精确
  分组，父子牌组只计一次；不可用状态显示“—/暂不可用”，不再冒充 0。
- 牌组统计、复习进度筛选和个人统计已移除 new/young/mature/leech 四档叙事；
  这些字段只作为内部调度兼容数据保留。
- 官方来源尚未接好 public stats/browser/options/uninstall repository 的动作已隐藏，
  防止错误落到 Legacy DAO/Manager。

明确未冒充完成的后续切片：

- 官方 revlog 尚未投影到统一的产品历史/统计 repository；当前官方 collection
  仍是唯一事实来源。
- `OfficialAnkiHomeDue` 仍是带 single-flight 刷新的静态快照，尚未迁成实例化、
  可观察且带 freshness 的 repository state。
- 官方牌组 public browse/stats/uninstall 需要官方 repository 后再开放；本轮采取
  fail-closed 隐藏，而不是用 Legacy 实现兜底。

## 1. 不再摇摆的产品决策

以下决策是后续代码评审的硬约束：

1. 用户侧只有两个结果：`不记得`、`记得`。
2. 新代码领域模型只使用 `RecallOutcome.forgotten/remembered`，不再把 Anki 的 1～5 数字质量分当作产品 API。
3. `不记得 -> Again`，`记得 -> Good`。`Hard/Easy` 仅保留为历史数据兼容或导入解码能力，不再出现在新界面和新业务 API 中。
4. 所有复习会话采用课程式外壳：课程卡片排版、进度、正反面揭示、AI/辅助动作、撤销和完成页一致。
5. 卡片正文可按来源不同渲染：普通课程内容使用 Flutter 组件；要求原样还原的官方 Anki 模板正文可继续使用 WebView，但 WebView 只能是统一外壳里的“卡片正文”，不能再自带一整套复习产品。
6. 一张卡、一次作答、一个唯一写入者。禁止同一次交互同时写 Turna SRS 和官方 Anki。
7. “今日重点”的通用 SRS 不再接管任何 Anki 卡片；Anki 到期只在 Anki 聚合入口展示。由课程进入的卡片默认是课程练习，不偷偷改变正式 Anki 排期。
8. 用户侧去掉“四象限记忆/新学、年轻、成熟、难点”这套主叙事。`leech` 可作为内部风险标记保留，但不是第四种记忆答案，也不应继续包装成四象限。
9. 官方 Anki 的集合、排期、revlog 以官方核心为唯一事实来源，遵守 ADR-0036；Turna 数据库只保存来源映射、课程投影和可重建缓存。
10. 旧 Anki 实现进入冻结和迁移状态，只修正确性、迁移与兼容问题，不继续增加独立功能。

### 1.1 文档优先级

现有文档出现冲突时，按下面顺序解释：

1. ADR-0036 的“官方 Anki 唯一事实来源”继续有效。
2. 本文覆盖旧文档中“四按钮、双产品路径、默认 Fidelity 复习”的产品决策。
3. `docs/anki-integration-design.md` 中自研 Anki 数据存储、四评分默认入口等内容视为历史实现说明，不再作为目标架构。
4. `docs/official-anki-migration/30-*`、`31-*`、`32-*` 中与本文冲突的四评分和双入口部分，应在施工 P6 统一标记为 superseded；其中关于官方集合唯一来源、原模板保真和失败不静默回退的约束继续保留。
5. ADR-0030 中页面本地撤销栈“以后再迁移”的延期项在 P1 结束，不再继续延期。

## 2. 当前系统地图

### 2.1 六类入口

| 入口 | 当前渲染/控制器 | 当前写入 | 主要问题 |
| --- | --- | --- | --- |
| 今日重点 · 通用 SRS | `SrsReviewScreen` | Turna SRS | 队列未排除旧 Anki，可能重复复习；找不到内容时显示内部 ID |
| 今日重点 · Anki | `AnkiReviewScreen` 聚合入口 | 根据后续路由变化 | 到期数、分组数、功能能力不是同一来源 |
| Anki · 旧导入复习 | `AnkiReviewSessionPage` + 合成 Lesson | Turna SRS | 套课程 VM，但另存撤销和配额；四按钮 |
| Anki · 官方复习 | `OfficialAnkiReviewPage` | 官方 Scheduler | 自绘整套页面；四按钮；与课程 UI/副作用割裂 |
| 课程 · 旧 Anki | `NewLessonScreen`/课程 renderer | Turna SRS | 与独立 Anki 复习行为和统计不同 |
| 课程 · 官方 Anki 投影 | `NewLessonScreen`/课程 renderer | 默认不写官方排期 | 看似学过，官方到期状态却可能没有变化 |

### 2.2 当前数据流

```text
PlayHub
├─ 今日重点 / SRS
│  └─ SrsProvider.getDueWords（当前会混入旧 Anki）
│     └─ SrsReviewScreen
│        └─ Turna FSRS + 本地历史/统计
│
└─ Anki
   └─ AnkiReviewScreen
      ├─ 旧导入 section
      │  └─ AnkiReviewSessionPage
      │     └─ 合成 Lesson -> LessonViewModel -> Turna FSRS
      │        └─ 页面又维护一套撤销/计数
      └─ 官方 section
         └─ OfficialAnkiReviewGate
            └─ OfficialAnkiReviewPage
               └─ 官方 Scheduler

课程树
├─ 内置课程 -> NewLessonScreen -> Turna FSRS
├─ 旧 Anki 投影 -> NewLessonScreen -> Turna FSRS
└─ 官方 Anki 投影 -> NewLessonScreen
   └─ 默认 courseGradesScheduler=false，未形成可靠的官方排期写入
```

### 2.3 四套被混用的语义

| 语义 | 值 | 出现位置 | 问题 |
| --- | --- | --- | --- |
| 二元记忆 | `fail/pass`、`unknown/known` | 通用 SRS、部分课程 | 名称不统一，但最接近目标模型 |
| Anki 四评分 | `Again/Hard/Good/Easy` | 两个旧 renderer、官方复习页 | 与目标产品决策冲突 |
| 数字质量分 | 1、2、3、4、5 | VM、桥接、兼容层 | `Hard` 在不同位置被解释为 2 或 3 |
| 四类熟练度 | new/young/mature/leech | 统计、文案 | 被误称为“四象限记忆”，和作答含义混在一起 |

### 2.4 两套正式账本与一条旁路

| 账本 | 应负责 | 当前额外/缺失责任 |
| --- | --- | --- |
| Turna Drift + FSRS | 内置课程、旧导入迁移期数据 | 通用 SRS 会误收旧 Anki；本地统计混合不同来源 |
| 官方 Anki collection/scheduler/revlog | 官方导入卡片 | 课程路径默认不写；部分管理/统计功能仍误用旧 DAO |
| 通用 SRS 旁路 | 只应负责非 Anki 的 Turna 内容 | 实际会把旧 Anki 再暴露为一条复习入口 |

## 3. 已确认的杂糅和矛盾清单

以下不是视觉差异，而是会造成用户状态、排期或数据理解错误的问题。

### A. 队列与到期数

1. 通用 `getDueWords` 没有排除 Anki ID，导致旧导入同时出现在“今日重点/SRS”和“Anki”中。
2. `SrsReviewScreen` 只认识课程词汇/表达 ID；遇到 Anki ID 时可能把内部 ID 当题面。
3. Anki 首页的分节到期数并非按真实 deck/section 查询；同一批导入会复用相同统计。
4. 官方总到期数被平均分配给多个导入，造成每个导入看起来都有“伪精确”的到期数。
5. 两条官方到期刷新实现对 learning 数量的计算并不一致。
6. 官方到期不可用状态存在于内存，但 UI 没有可靠地表达“未知”，容易把未知显示成 0。
7. 首页存在未形成稳定职责的静态全局 due 状态，增加刷新竞态和测试污染风险。

### B. 调度与评分

8. 核心枚举把 `Hard` 定义为质量 3，官方桥接/练习表面又把质量 2 当 `Hard`、3 当 `Good`。
9. 旧 Anki renderer 与官方页面都保留四按钮，课程/通用 SRS 又使用二元回答。
10. 失败预览固定按“第一次当天失败”计算，但真实 Turna relearn 阶梯包含 10m/30m/2h/明天，成熟卡第一次失败可能直接是 30m。
11. 官方课程桥接是可选注入；未传回调时仍可能返回成功，让调用方误以为已经落账。
12. `courseGradesScheduler` 默认关闭，官方课程练习与官方正式排期脱节。
13. 旧导入独立复习通过“合成 Lesson”接入 Lesson VM，课程进度语义与正式复习语义彼此污染。

### C. 撤销、历史与副作用

14. 旧 Anki 页面先调用 SRS 撤销，随后 Lesson VM 再撤销一次，存在一次点击回滚两条历史的风险。
15. 页面和 VM 各自捕获一份 undo state，没有共享同一个 review event ID，也没有事务边界。
16. 不同入口对错题本、学习统计、连续学习、宝石/奖励的处理不同。
17. 官方练习路径可能按每一道正确题触发 lesson-complete 类事件，而课程路径通常按会话完成结算。
18. 本地统计只读取 Turna SRS/grammar 历史，官方 revlog 基本不可见；用户看到的统计不代表全部复习。
19. `correctCount/incorrectCount` 在部分会话按“做过”统计，而不是按二元记忆结果统计。

### D. 管理功能与来源能力

20. 官方 deck 在聚合页仍显示旧导入的每日配额或设置含义。
21. 统计页、卡片浏览、暂停/恢复、卸载部分仍调用 Legacy DAO/Manager；官方来源可能显示空数据、静默不生效或清错数据。
22. UI 没有基于来源声明能力，导致“不支持”被伪装为“按钮存在但无效果”。
23. 官方失败是否回退旧实现、旧导入如何迁移、OpenHarmony 如何处理，散落在 flag 和页面条件中，没有统一状态机。

### E. 文案、测试与文档

24. 同一含义同时使用“认识/不认识”“记得/不记得”“Again/Good”“会/不会”。
25. “Hard/Easy”与“new/young/mature/leech”都被用户理解成四档记忆程度，实际一个是作答、一个是统计分类。
26. 测试明确锁定 `Hard` 和 `Easy` 的独立行为，导致产品改为二元后不能只改按钮。
27. changelog 和旧设计文档仍宣称双轨、四评分是既定方向。
28. 施工前静态分析基线本身不干净，约 168 个问题、其中 7 个 error；若不先建立基线，重构期间无法判断新增回归。

因此，本轮不是简单“换皮”。如果只把按钮改成两个，仍会保留假到期数、双撤销、错账本和假统计。

## 4. 目标领域模型

### 4.1 唯一用户作答模型

```dart
enum RecallOutcome {
  forgotten,
  remembered,
}
```

禁止在 widget、page、controller 之间传裸 `int quality`。历史兼容值只能在账本 adapter 的边界解码。

### 4.2 强类型来源

```dart
sealed class ReviewSource {
  const ReviewSource();
}

final class TurnaCourseSource extends ReviewSource { /* ... */ }
final class LegacyAnkiSource extends ReviewSource { /* migration only */ }
final class OfficialAnkiSource extends ReviewSource { /* collection/deck/card */ }
```

不允许再通过 `id.startsWith('anki-')` 在 UI 里推断来源。字符串前缀只允许存在于一次性迁移、解析器或 repository 边界。

### 4.3 统一复习条目

```dart
class ReviewItem {
  final String sessionItemId;
  final ReviewSource source;
  final ReviewContent content;
  final ReviewCapabilities capabilities;
  final ReviewSchedulingKey schedulingKey;
}
```

`ReviewContent` 描述题面、答案、音频、图片、输入题等课程渲染信息；`ReviewSchedulingKey` 只交给所属账本，不暴露给 UI。

### 4.4 唯一账本接口

```dart
abstract interface class ReviewLedger {
  Future<ReviewDueSummary> dueSummary(ReviewScope scope);
  Future<ReviewPreview> preview(
    ReviewSchedulingKey key,
    RecallOutcome outcome,
  );
  Future<ReviewEventReceipt> answer(
    ReviewSchedulingKey key,
    RecallOutcome outcome,
  );
  Future<void> undo(ReviewEventReceipt receipt);
  Future<ReviewHistoryPage> history(ReviewScope scope);
}
```

两个实现：

- `TurnaReviewLedger`：`forgotten -> Again`，`remembered -> Good`，由 Turna FSRS 计算真实间隔。
- `OfficialAnkiReviewLedger`：`forgotten -> Again`，`remembered -> Good`，由官方 scheduler 写 collection/revlog。

`ReviewEventReceipt` 必须包含唯一事件 ID、来源、前后状态或官方 undo token。撤销必须针对 receipt，禁止“删除最近一条”式的猜测。

### 4.5 会话与账本分离

```text
UnifiedReviewPage（课程式 UI）
  └─ ReviewSessionController（队列、翻面、提交、撤销、完成）
     ├─ ReviewItemRenderer（课程式题面/交互）
     ├─ ReviewLedgerResolver（按来源选唯一账本）
     └─ ReviewSessionEffects（错题、统计、奖励，一次性结算）
```

正式复习不再把 `LessonViewModel` 当复习控制器。可复用课程 renderer 和视觉组件，但课程节点解锁、章节进度等副作用不得被 Anki 正式复习隐式触发。

## 5. 队列所有权与写入规则

### 5.1 队列所有权

| 场景 | 展示什么 | 是否写正式排期 |
| --- | --- | --- |
| 今日重点 · 通用 SRS | 仅 Turna 非 Anki 内容 | 是，Turna ledger |
| 今日重点 · Anki | 旧导入迁移期 + 官方 Anki 的真实 due | 是，按来源 ledger |
| 课程内普通内容 | 当前课程练习 | 是，Turna ledger |
| 课程内旧 Anki 投影 | 当前课程练习 | P2 前保持旧行为；迁移完成后由明确策略决定 |
| 课程内官方 Anki 投影 | 当前课程练习 | 默认否；若以后允许，必须显式显示“计入 Anki 排期”并走同一 ledger |
| 卡片预览/浏览器 | 指定卡片 | 否 |

### 5.2 一次作答的事务顺序

```text
用户点击“记得/不记得”
  1. Controller 锁定当前 item，阻止双击
  2. Ledger 预览并提交唯一调度事件
  3. 得到 ReviewEventReceipt
  4. 记录二元产品历史与来源引用
  5. 触发错题/统计副作用
  6. 推进队列并允许 undo
```

任一步失败时：

- 不得把 UI 提前推进为已完成；
- 不得静默切换另一个账本；
- 已产生 receipt 的后续失败必须补偿或标记待恢复；
- 官方核心不可用时显示“当前无法写入 Anki 排期”，而不是当作 0 到期或成功练习。

### 5.3 “不记得”的统一口径

产品语义统一为“本题未成功回忆”，但时间阶梯由账本负责：

- Turna：沿用并收口为一套 FSRS/relearn 状态机；10m/30m/2h/明天等步骤由当前卡片状态决定。
- 官方 Anki：使用 collection 中的 deck option、learning/relearning steps 和 scheduler 返回结果。
- UI 文案展示账本返回的 `ReviewPreview.nextDueAt/intervalLabel`。
- 禁止继续用固定“`不认识 · 10分钟`”或无状态的 `previewFailMinutes(word)` 猜测。

## 6. 历史、统计与迁移口径

### 6.1 产品历史

新增或规范化以下字段，实际表名由实现阶段按现有 schema 决定：

```text
review_event_id       唯一，支持精确撤销和幂等
source_type           turna / legacy_anki / official_anki
source_ref            本地实体或官方 card/revlog 引用
outcome               forgotten / remembered
native_rating         可空，仅兼容与排障，不用于产品统计
reviewed_at
next_due_at            可空，以 ledger 返回为准
session_id
undone_at              可空，保留审计，不物理猜删“最近一条”
```

旧质量分回填规则仅用于历史迁移：

```text
quality < 3  -> forgotten
quality >= 3 -> remembered
```

注意：回填是产品统计映射，不重放调度、不修改官方 revlog，也不意味着运行时继续接受任意质量分。

### 6.2 统计

统一统计读取层，不统一抄写账本：

```text
ReviewAnalyticsRepository
├─ Turna history reader
├─ Official revlog reader
└─ normalized binary event projection/cache
```

首版统一指标只保留用户可解释项：

- 今日已复习/待复习；
- 记得率与不记得次数；
- 连续复习天数；
- 下次到期分布；
- 风险卡片/反复遗忘（可由 leech 或失败次数推导）。

`new/young/mature/leech` 可留作内部诊断或高级筛选，但移出首页“四象限记忆”展示，不再与两个作答按钮并列解释。

### 6.3 迁移原则

1. schema 只做向前兼容添加，先双读、再切读、最后停止旧写；不可直接破坏现有历史。
2. 官方 revlog 不复制为第二份调度事实，只做只读投影/缓存，缓存必须可重建。
3. 旧导入未迁移完成前，由 `LegacyAnkiSource` 明确标识；不把它伪装成官方卡片。
4. 每次迁移记录版本、数量、失败原因和可重试状态。
5. 删除旧表、旧前缀和旧 Manager 放到 P6，并要求备份/恢复演练通过后再执行。

## 7. 分阶段施工

每个阶段都应能独立合并、验证和回滚。不要把 UI、调度、历史迁移一次性塞进一个 PR。

### P0：冻结语义与建立可测基线

目标：让后续改动能区分“原有问题”和“新回归”。

施工：

- 将本文作为 Anki 统一工作的产品/工程基线。
- 记录当前 `flutter analyze` 的 168 个问题和 7 个 error；先修到 error 为 0，或建立经确认的 baseline allowlist。
- 为现有入口补最小快照测试：队列来源、按钮数、写入者、撤销条数、到期数。
- 增加架构守卫测试：UI 不得直接提交裸质量分；官方 source 不得调用 Legacy Manager；通用 SRS 队列不得含 Anki source。
- 新功能暂停继续扩展四评分、页面本地 undo 和静态全局 due 状态。

重点文件：

- `lib/core/sm2.dart`
- `lib/application/srs_provider.dart`
- `lib/application/lesson_viewmodel.dart`
- `test/core/fsrs_engine_test.dart`
- `test/views/anki_card_renderer_test.dart`
- `test/views/anki_html_card_renderer_test.dart`

完成标准：

- CI 能清晰指出本分支新增的 analyze/test 回归；
- 现状测试能复现 P1 要修的队列、计数和双撤销问题；
- 没有行为改动。

回滚：只撤测试/基线配置，不涉及用户数据。

### P1：先修数据正确性

目标：即使 UI 尚未统一，也不能继续重复复习、显示假数字或一次撤销两条历史。

#### P1-A 队列与到期数

- 给 SRS 查询增加强类型 scope，通用今日重点明确排除 `LegacyAnkiSource` 和 `OfficialAnkiSource`。
- 删除按导入平均分配官方到期数的逻辑；只能显示真实 section/deck count。
- 暂时无法拿到真实分组数时显示“—/暂不可用”，不得伪造。
- 合并官方 due 刷新入口，统一是否包含 new/learning/review 的定义。
- 静态 due 状态至少增加 generation/request token，避免旧请求覆盖新结果；P2 再迁到 repository state。

重点文件：

- `lib/application/srs_provider.dart`
- `lib/views/play/play_hub_screen.dart`
- `lib/views/review/srs_review_screen.dart`
- `lib/application/anki_official/engine/official_anki_home_due.dart`
- `lib/application/anki_official/engine/official_anki_home_due_sync.dart`
- `lib/application/anki_official/migration/official_anki_production_router.dart`
- `lib/views/anki/anki_review_screen.dart`

验收：

- 同一卡片不会同时出现在通用 SRS 和 Anki due；
- 多个官方导入不会再平分同一个总数；
- unknown、0、加载中、错误四种状态可区分；
- 刷新前后总数满足 `total = new + learning + review` 的同一定义。

#### P1-B 撤销与评分错位

- 明确唯一撤销 owner：短期内保留 VM 或页面其中一个，另一套删除。
- 撤销以 event receipt/ID 定位；补测试保证一次点击只撤一条调度和一条产品历史。
- 修正数字质量的 `Hard` 2/3 冲突；在 P3 删除四评分前，所有兼容层先使用同一映射。
- `OfficialAnkiCourseGradesBridge` 无写入 callback 时返回明确失败，不得假成功。

重点文件：

- `lib/views/anki/anki_review_session_page.dart`
- `lib/application/lesson_viewmodel.dart`
- `lib/core/sm2.dart`
- `lib/application/anki_official/engine/official_anki_course_grades_bridge.dart`
- `lib/application/anki_official/official_anki_feature_flags.dart`

验收：

- 连续复习 A、B 后撤销 B，只恢复 B，A 的历史与排期完全不变；
- 页面销毁/重进后不会再次撤销旧事件；
- 所有旧兼容入口对相同 raw rating 得到相同解释；
- 未注册官方写入能力时 UI 不报告成功。

回滚：P1 不做破坏性 schema 删除；可按子 PR 回滚查询、计数、撤销改动。

### P2：建立来源分发层

目标：先把“谁拥有这张卡、谁可以对它做什么”收口，再换 UI。

施工：

- 引入 `ReviewSource`、`ReviewLedger`、`ReviewLedgerResolver` 和 receipt 模型。
- 把 Turna FSRS 包装为 `TurnaReviewLedger`。
- 把官方 scheduler 包装为 `OfficialAnkiReviewLedger`，保持 ADR-0036 的唯一事实来源。
- 引入 `AnkiDeckRepository`/capabilities，按来源分发 due、stats、browse、suspend、uninstall。
- 官方能力尚未实现时隐藏或禁用并解释原因，禁止回落到 Legacy DAO。
- 将聚合首页从静态 globals 迁到可观察 repository state，带 loading/error/freshness。

建议能力模型：

```dart
class ReviewCapabilities {
  final bool canSchedule;
  final bool canUndo;
  final bool canSuspend;
  final bool canBrowse;
  final bool canUninstall;
  final bool canRenderOriginalTemplate;
}
```

验收：

- 一张卡的 source 在进入 session 前确定，session 内不可变；
- 任何 `answer()` 只有一个 ledger 调用；
- 官方 deck 的统计/暂停/卸载不再触碰 Legacy 表；
- capability 测试覆盖 Android 官方、旧导入、普通课程与官方不可用场景。

回滚：新 adapter 可在 flag 后接入，旧页面暂时仍使用 adapter，不要求同 PR 换 UI。

### P3：二元记忆语义落地

目标：所有用户入口只出现“记得/不记得”。

施工：

- 增加 `RecallOutcome`，会话层只接受二元结果。
- Turna adapter 映射 `forgotten -> Again`、`remembered -> Good`。
- Official adapter 映射 `forgotten -> Again`、`remembered -> Good`。
- 将两个旧 Anki renderer、HTML renderer、官方复习页和课程相关交互改为同一二按钮组件。
- 主按钮文案固定为“记得”“不记得”；不再混用“认识/不认识”。
- 删除 UI 的 `Again/Hard/Good/Easy` 四列预览；只展示两个由 ledger 返回的真实下次时间。
- raw rating、`AnkiReviewRating.hard/easy` 等移入 legacy compatibility namespace，标注 deprecated，禁止新引用。

重点文件：

- `lib/views/lesson/components/interactions/anki_card_renderer.dart`
- `lib/views/lesson/components/interactions/anki_html_card_renderer.dart`
- `lib/views/anki_official/official_anki_review_page.dart`
- `lib/views/anki_official/official_anki_practice_review_surface.dart`
- `lib/l10n/app_strings.dart`
- `lib/core/sm2.dart`
- `lib/core/fsrs_engine.dart`

测试迁移：

- 删除“Hard 与 Good 必须有不同按钮行为”“Easy 独立按钮”类产品测试。
- 保留兼容层解码测试，但测试名称明确为 migration compatibility。
- 所有 widget test 断言只有两个可提交按钮。
- 参数化测试所有入口：一次 `forgotten/remembered` 各产生一次且仅一次账本写入。

验收：

- 全局搜索用户可见字符串，无 Hard/Easy/Again/Good 残留；
- 新业务代码中无裸 `quality: int`；
- 两个结果的 interval preview 与实际 receipt 一致。

回滚：adapter 保留旧 raw rating 解码，因此可回滚 UI；不可回滚已经完成的 P1 正确性修复。

### P4：统一为课程式复习会话

目标：入口不同、卡片正文不同，但复习产品只有一套。

施工：

- 建立 `UnifiedReviewPage` 与 `ReviewSessionController`。
- 提取课程已有的顶部进度、卡片容器、正反面揭示、音频、辅助信息、AI 动作、底部二元按钮、撤销和完成页。
- 让普通课程、旧 Anki、官方 Anki 都提供 `ReviewItem`，不再各自实现页面状态机。
- 删除旧 Anki “合成 Lesson 作为正式复习”的耦合；课程 renderer 通过 adapter 被 session 复用。
- 官方原模板模式仅替换 `ReviewContentBody`，外层导航、按钮、进度、错误和完成态保持统一。
- 统一键盘、触觉、无障碍标签、loading/error/empty 状态和返回确认。

建议组件边界：

```text
UnifiedReviewPage
├─ CourseStyleReviewScaffold
│  ├─ ReviewProgressHeader
│  ├─ ReviewContentBody
│  │  ├─ FlutterCourseCardBody
│  │  └─ OfficialTemplateWebViewBody
│  ├─ ReviewRevealArea
│  ├─ BinaryRecallBar
│  └─ ReviewUndoBar
└─ UnifiedReviewCompletion
```

明确不做：

- 不把官方 card HTML 强制重写成 Flutter；
- 不把 Lesson VM 的章节解锁、课程完成奖励整套搬进正式复习；
- 不在这个阶段改官方 scheduler 算法。

验收：

- 从三个入口进入时，外壳、进度、二按钮、撤销和完成页一致；
- renderer 只负责内容，不直接写调度；
- session controller 不依赖字符串 ID 前缀判断来源；
- 官方 WebView 崩溃/不可用不会切到另一个账本。

回滚：按入口逐个切换 flag；统一页和旧页可短期并存，但同一来源在生产只能启用一条正式复习路由。

### P5：统一失败算法呈现、历史、统计与副作用

目标：用户在任何入口看到的“已复习、记得率、下次时间、撤销、奖励”使用同一口径。

施工：

- 将失败/成功预览改为 ledger authoritative preview，删除固定 10 分钟文案和无状态猜测。
- 引入二元产品历史字段与 event receipt；旧记录按兼容规则回填。
- 建立 `ReviewAnalyticsRepository`，合并 Turna history 和官方 revlog 的只读标准化结果。
- 统一 session effects：错题在 `forgotten` 时记录；奖励和连续学习按会话幂等结算；撤销同步补偿 effects。
- 移除首页四象限卡片，改为“待复习、今日完成、记得率、反复遗忘”或更少的可解释指标。
- 明确课程练习是否写正式官方排期。默认保持不写；若产品以后打开，必须是用户可见的模式并复用同一个 Official ledger。

验收：

- 同一条作答在调度账本、产品历史、统计、错题和奖励中使用同一个 event ID；
- 撤销后这些投影一致恢复；
- 官方和 Turna 历史可以在同一统计页按来源筛选并正确汇总；
- UI 预览时间与重新读取的实际 due 一致；
- 用户侧不存在“四象限记忆”概念。

迁移回滚：

- 新字段先双写并提供重建脚本；
- 统计 projection 可删除重建；
- 不修改官方原始 revlog；
- 迁移失败只影响新统计，不影响卡片排期。

### P6：退役旧实现与文档收口

目标：清掉在 P1～P5 已无调用的历史实现，而不是带着两套产品长期运行。

施工：

- 完成旧导入到官方/明确 Legacy 冻结路径的迁移策略与恢复演练。
- 删除无引用的页面本地 undo、静态 due globals、合成 Lesson 复习入口、旧四评分 widget。
- 删除已经被 adapter 取代的 Legacy DAO/Manager 直连；删除前做数据备份和引用扫描。
- 收口 feature flags，保留故障隔离 flag，不保留永久双产品 flag。
- 更新 changelog、ADR 索引、旧设计文档的 superseded 标记和测试名称。
- 明确 OpenHarmony：若官方核心不可用，显示受支持的迁移/只读状态；不得悄悄切换成语义不同的 Legacy 复习。

验收：

- 六类入口最终复用一套 session，只有队列 scope 与 renderer/ledger adapter 不同；
- 生产路径无四评分 UI、无双 undo、无假分摊 due；
- 官方卡片所有调度与管理操作只经过官方 repository；
- 删除项有 `rg` 引用为零、完整测试、备份和回滚记录；
- 所有相关文档描述同一产品事实。

## 8. 建议 PR 切片与顺序

建议以小 PR 排序，数字不是版本号：

1. `anki-baseline-tests`：复现重复队列、假计数、双撤销、评分错位。
2. `anki-queue-ownership`：通用 SRS 排除 Anki，修内部 ID fallback。
3. `official-due-truth`：移除平均分配，统一 due 定义和 unavailable 状态。
4. `review-undo-single-owner`：一次撤销只回滚一个 event。
5. `review-source-and-ledger`：引入 source、ledger、receipt，不换 UI。
6. `anki-management-dispatch`：stats/browser/suspend/uninstall 按来源分发。
7. `binary-recall-domain`：二元 outcome 与 adapter 映射。
8. `binary-recall-ui`：所有入口换二按钮和真实 preview。
9. `unified-review-session`：课程式外壳先接旧 Anki，再接官方 Anki。
10. `review-history-v2`：二元事件、幂等 effects、统计 projection。
11. `remove-memory-quadrants`：替换四象限 UI/文案。
12. `legacy-retirement`：迁移完成后删除死代码和过期 flags/docs。

前四个 PR 是止血，不应等待统一 UI 完成。

## 9. 文件级施工地图

| 区域 | 当前关键文件 | 目标动作 |
| --- | --- | --- |
| 首页入口 | `lib/views/play/play_hub_screen.dart` | 只消费 repository 的 typed due state，区分 0/unknown/error |
| 通用 SRS | `lib/application/srs_provider.dart`、`lib/views/review/srs_review_screen.dart` | 排除 Anki source，去内部 ID fallback，接统一 session |
| Anki 聚合页 | `lib/views/anki/anki_review_screen.dart` | 真实分组数、来源能力、统一 session 路由 |
| 旧复习页 | `lib/views/anki/anki_review_session_page.dart` | 先修双 undo，后由统一 session 取代 |
| 课程 VM | `lib/application/lesson_viewmodel.dart` | 移除正式 Anki 复习职责和裸 quality；保留课程职责 |
| 旧 renderer | `lib/views/lesson/components/interactions/anki_card_renderer.dart` | 只渲染内容/二元交互，不直接决定账本 |
| HTML renderer | `lib/views/lesson/components/interactions/anki_html_card_renderer.dart` | 同上；WebView 作为正文能力 |
| 官方 gate/page | `lib/views/anki/anki_official_review_gate.dart`、`lib/views/anki_official/official_anki_review_page.dart` | gate 只选能力/adapter，page 由统一 session 取代 |
| 官方练习 surface | `lib/views/anki_official/official_anki_practice_review_surface.dart` | 删除四评分和逐题 lessonComplete 副作用 |
| 官方 bridge | `lib/application/anki_official/engine/official_anki_course_grades_bridge.dart` | 收进 Official ledger；无 callback 不得成功 |
| due 聚合 | `lib/application/anki_official/engine/official_anki_home_due*.dart` | 迁入 repository，取消静态状态与伪分配 |
| 官方 router | `lib/application/anki_official/migration/official_anki_production_router.dart` | 返回真实 scope 统计，不按导入均分 |
| 统计 | `lib/application/memory_curve_provider.dart`、`lib/application/review_progress_provider.dart` | 读取统一 analytics projection，保留来源筛选 |
| 管理 | `lib/views/anki/anki_deck_stats_page.dart`、`anki_card_browser_page.dart`、`lib/application/anki/anki_deck_manager.dart` | 来源 repository/capability 分发 |
| 算法 | `lib/core/sm2.dart`、`lib/core/fsrs_engine.dart`、`lib/core/fsrs_relearn.dart` | 二元边界，失败预览使用真实状态，旧评分仅兼容 |
| 文案 | `lib/l10n/app_strings.dart` | 统一“记得/不记得”，移除四象限主叙事 |
| DI | `lib/di/injection.config.dart` 及注册源 | 显式注册 resolver/ledgers，杜绝可选桥接假成功 |

## 10. 测试矩阵

### 10.1 单元测试

- `RecallOutcome` 到两个 ledger native rating 的映射。
- 历史 raw quality 的只读兼容映射。
- Turna 不同 relearn 状态下 forgotten preview 与实际 answer 一致。
- 官方 preview/answer 使用同一 scheduler 状态。
- due scope 排除/包含规则。
- 一次 receipt 精确撤销，不影响前一事件。
- effects 幂等：重试不会重复错题、奖励或完成次数。
- stats projection 合并 Turna 与官方来源但不重复计数。

### 10.2 Widget/Golden 测试

- 所有复习入口只有“记得/不记得”两个提交按钮。
- 普通课程、旧 Anki、官方 Anki 的统一外壳 golden 一致。
- HTML/WebView 只替换卡片正文区域。
- loading、empty、unknown due、error、offline 和 official unavailable 状态。
- undo 可见性与超时行为一致。
- 无障碍标签不再出现 Hard/Easy/Again/Good。

### 10.3 集成测试

| 场景 | 必验结果 |
| --- | --- |
| 同一卡片从今日重点与 Anki 查询 | 只属于一个正式 due 队列 |
| Turna 卡点击不记得 | 只写 Turna，一条历史，真实下一时间 |
| 官方卡点击记得 | 只写官方 collection/revlog，一条产品投影 |
| 官方写入失败 | UI 不推进，不写 Turna fallback |
| 连做 A/B 后撤销 | 只撤 B，重启后状态仍正确 |
| 课程预览官方卡 | 默认不改变官方 due |
| 多导入/多 deck | 每组显示真实 count，总数为真实求和 |
| 卸载官方 deck | 不调用 Legacy Manager；映射与 collection 按明确事务处理 |

### 10.4 架构守卫

可用 lint/依赖测试或 `rg` 脚本实现：

- `views/**` 不得出现新的 `quality: 1..5` 调度调用。
- 官方 source 路径不得 import Legacy DAO/Manager。
- `SrsReviewScreen` 不得直接接受 Anki source。
- renderer 不得 import scheduler/DAO。
- session controller 不得依赖 `LessonViewModel`。
- 新 UI 字符串不得出现四评分标签。

## 11. 发布、观测与回滚

### 11.1 需要的观测

按来源记录匿名聚合指标：

- due 查询成功率、耗时和 freshness；
- answer 成功/失败/重试率；
- 同一 interaction 的 ledger write count，目标恒为 1；
- receipt 与产品历史投影不一致数量；
- undo 成功率；
- unknown due 被显示为 0 的次数，目标为 0；
- 同一卡跨队列重复出现数量，目标为 0。

不得上报卡片正文、答案或用户导入内容。

### 11.2 Feature flag 原则

只允许围绕入口切换和故障隔离的短期 flag：

- `unifiedReviewSessionEnabled`
- `binaryRecallEnabled`
- `reviewHistoryV2ReadEnabled`

禁止继续添加“旧四评分/新四评分”“课程写/官方写同时开”这类组合爆炸 flag。每个 flag 要有 owner、删除日期和回滚路径。

### 11.3 回滚边界

- UI/session 可按来源回滚到旧页面，但仍必须经过 P2 ledger adapter，不能恢复双写。
- 新统计 projection 可丢弃重建。
- schema 迁移阶段只加字段，不在可回滚窗口删除旧字段。
- 官方 collection/revlog 不由回滚脚本重写。
- P1 的重复队列、假 due、双 undo 修复不作为 UI 回滚的一部分撤销。

## 12. Definition of Done

只有同时满足以下条件，才算“统一完成”：

- [x] 所有用户复习入口只提供“记得/不记得”。
- [x] 所有入口使用课程式会话外壳、进度、撤销和完成页。
- [x] 一张卡一次作答只有一个账本写入。
- [x] 通用 SRS 不再出现任何 Anki 卡片。
- [x] 官方 Anki 排期与 revlog 只由官方核心维护。
- [x] 到期数按真实 scope 计算，不平均分配、不用 unknown 冒充 0。
- [x] 失败/成功预览来自实际 ledger，和提交后的真实 due 一致。
- [ ] 一次撤销只恢复一个 review event，并补偿对应统计/错题副作用。
- [ ] 官方与 Turna 历史可统一展示、按来源解释且不重复计数。
- [x] 用户侧移除四评分和“四象限记忆”叙事。
- [ ] 官方 deck 的浏览、暂停、卸载、统计均按来源分发，不误调用 Legacy。
- [ ] 旧文档、测试、changelog 不再宣称四评分或永久双轨是目标方向。
- [x] analyze 无新增 error，相关核心单元/widget/调度与迁移测试全部通过。
- [ ] 旧实现删除前完成备份、恢复演练、引用归零和分阶段发布验证。

### 12.1 本轮验货记录

- 精确回归组共 102 项通过，覆盖 Turna receipt/精确撤销、二元
  FSRS relearn、旧导入 batch、课程练习边界、官方 scheduler、
  answer-present ACK、迁移 closeout/playbook 与真实 deck-tree due。
- 课程内 Anki/HTML 二元 renderer 与 lesson flow 补充回归 22 项通过。
- 对本轮 19 组核心生产/测试路径执行 `flutter analyze`：
  `No issues found`。
- 全仓 `flutter analyze` 现为 142 条既有 warning/info、零 error；
  其中本轮 Anki 核心路径为零项，其余基线债务未扩大本施工范围。
- 架构扫描确认：独立 Anki/SRS 正式复习不再依赖
  `LessonViewModel`；官方正式页无 Hard/Easy 提交入口；三个用户
  统计页无四象限叙事；官方正式复习页不引用 Legacy DAO/Manager。
- 全仓库 `git diff --check` 仍会报出
  `lib/domain/course/interaction.dart` 的既有 CRLF/行尾空白；该文件属并行
  用户改动，本轮未擅自重写。本轮目标文件定向 `diff --check` 通过。

## 13. 第一批实际开工建议

不要先做大页面重构。第一轮只做三个可验证的止血包：

1. **队列止血**：通用 SRS 排除所有 Anki source；补重复队列回归测试。
2. **数字止血**：删除官方 due 平均分配，统一 new/learning/review 定义，unknown 明示。
3. **历史止血**：旧 Anki 撤销收为唯一 owner；补“复习 A/B 后只撤 B”的持久化测试，同时修正 Hard 2/3 的兼容映射。

这三项完成后，再引入 ledger adapter 和统一 UI。否则新 UI 只会把旧错账包装得更一致。
