# ADR 0037 — Anki 课程与复习大一统合同

- 状态：已接受（施工中；**2026-08-29 第二次修订为现行真源**）
- 日期：2026-08-20
- 修订：
  - 2026-08-29（第一次）：按 `CourseScope` 切开练习队列；导入 Anki 不写错题本 / Turna SRS。其中「废止 introduced、新卡直接进 Anki 复习」已被同日第二次修订取代。
  - 2026-08-29（第二次，现行）：解锁粒度 = **一个 Lesson**；第一遍只解锁、不写 scheduler（方案 A）；有导入历史的卡视为已解锁；重做已完成课 = 该课全部卡提前复习。
  - 2026-08-29（第三次）：选项 A 今日新卡名额覆盖刚解锁的那一课；重做跳过今日已官方评分的卡。
- 取代：anki-review-unification-construction-plan 中与本 ADR 冲突的“已完成”表述；官方迁移文档中与本决策冲突的「未学可复习 / 课内即写 scheduler」口径；**本文件 2026-08-29 第一次修订中「新卡必须直接进 Anki 复习 / introduced 不得过滤队列」**
- 关联：[ADR 0036](./0036-official-anki-core-migration.md)、[ADR 0041](./0041-ohos-product-eol.md)；身份模型仍见 [`docs/anki-course-review-unification-plan.md`](../anki-course-review-unification-plan.md)

---

## 决策（现行）

语言课与自行导入的 Anki 牌组是两套产品。练习入口按 `CourseScope` 切开；导入 Anki 的排期只走官方 scheduler。

### 1. 按 `CourseScope` 隔离入口与写入

判别只用 typed `CourseScope`（`BuiltinCourseScope` / `OfficialAnkiCourseScope` / `LegacyAnkiCourseScope`），经 `CourseScopeCodec` 编解码。新代码不得用 `id.startsWith('anki-')` / `'official-anki-'` 推断 backend 或课种。

| Scope | 练习页允许的复习入口 | 禁止 |
|---|---|---|
| 语言课（builtin） | 错题复习、单词复习、语法复习 | Anki 复习、把 Anki 到期混进「今日复习」、智能开始跳进 Anki |
| 导入 Anki（official / legacy） | **仅 Anki 复习** | 错题复习、单词复习、语法复习，以及薄弱单词等依赖错题本 / Turna SRS 的入口 |

同一套隔离适用于：练习页网格与「开始今日复习」Hero、智能开始、个人页快捷 chip、复习进度/统计的待复习构成。

Playground 仍仅语言课。Anki scope 下不恢复 Playground。

导入 Anki 卡 **不得** 写入 `MistakeProvider`、`SrsProvider`、`GrammarReviewProvider`，不得经错题本进入薄弱单词 / SRS 导师 / AI 诊断。遗忘只允许进官方 Again，或不评分。

Legacy-owned 源 fail-closed，不降级 Turna SRS。Official 运行时不可用（含非 Android，ADR 0041）时 Anki 队列为 `unavailable`，不得改切语言三队列。

### 2. 身份仍统一，禁止双写

```text
CanonicalCardKey
  = CourseCardPlacement
  = active CardPresentation
  = StudyLedgerOwner.officialAnki   // 导入 Anki 卡
```

Turna FSRS 只服务语言课词条与语法点。Official 写入失败不得回落 Turna。语言课内容不得写入 Official collection。

### 3. 导入 Anki 的学习闭环

```text
导入
  → 在「课程」里完成某一个 Lesson（第一遍 = 学会 / 解锁）
  → 该 Lesson 完成前：这一课的卡不能进入 Anki 复习
  → 完成后：卡交给官方算法（New ∪ Learn ∪ Review）
  → 到期出现在「Anki 复习」——这里才是新卡的第一次官方评分
        不认识 = Again    认识 = Good
  → 若重做已完成的 Lesson：该课所有卡视为提前复习到
        对 = Good          错 = Again
        整课做完再 flush；中途退出不写官方
```

正式复习入口仍是 `FormalReviewLauncher` → 共享 `AnkiReviewSessionRoute` / `OfficialReviewSession`。四档 UI 若出现，只是 presentation；rating 合法性以官方为准。

### 4. 正式复习资格

解锁粒度是 **一个投影 Lesson**，不是整副牌组、不是 Section/Unit、也不是单题提交。

```text
正式可复习
  = 官方 scheduler 队列（New ∪ Learn ∪ Review）
    ∩ active placement
    ∩ 已解锁
    ∩ not suspended / buried / retired

已解锁 ≔ 所属 Lesson 已完成
        ∨ 导入历史证明已学（collection 中 reps ≥ 1 或存在 revlog）
```

- **第一遍（方案 A）只解锁，不写 Official scheduler。** 课内对/错不记错题本、不写 Turna SRS、也不 `answerCard`。完成后该课全部卡进入「可被官方队列选中」；新卡按官方 New 出现在 Anki 复习，**那里的第一次 Again/Good 才是官方首次评分**。禁止下课再打一遍分，避免与 Anki 复习双写。
- **今日新卡名额（选项 A）**：第一遍完成课时，对该课卡片所在官方牌组抬高**当天**剩余新卡名额（`extend_new` / Custom Study NewLimitDelta），使剩余 ≥ 本课独立 cardId 数。不永久改牌组 `new_per_day` 预设。重做课不叠加名额。缺引擎 capability 时 fail-closed（解锁仍成功）。
- **不得**在每道题提交时 `markFromLesson`。中途退出的课，已做的题不得漏进 Anki 复习。
- 有导入历史的卡视为已解锁，不必为了进 Anki 复习再上完对应课；官方间隔不重置为新卡。
- `CardIntroductionStore` 的 introduced 语义就是本条「已解锁」，继续作为正式队列与 Play 到期数的过滤条件。
- 到期数只读 `OfficialFormalDueRepository`；`unavailable` 不是 0。语言课到期与 Anki 到期不得混加给另一侧看。

Anki 复习空状态可以说明「先完成课程里的一课」或「暂无到期」；不得再暗示「答过错题就会进 Anki 复习」。

### 5. 投影课树与重做

Official-first 导入仍投影 Section/Unit/Lesson。Anki scope 下课树是 **第一遍学会的地方**，不是与 Anki 复习平行的 Turna 队列。

- 第一遍：浏览 + 作答 + 完成课 → 只解锁。
- **重做**（该 `lessonId` 已在完成集合中）：本趟结束时，对该课 **今日尚未官方评分** 的 cardId 写一条官方评分（有一次客观错 → Again，全对 → Good），视为提前复习。今日已 `rated:1` 的卡只当练习、不改间隔。实现必须走官方 `answerCard` / 等价 queue（例如临时 filtered deck），失败 fail-closed 且对用户可见，不得 invent 另一套 due。中途退出整趟不写。
- 普通词汇默认 Flip，不得仅因干扰项生成第二张正式 MCQ。课程式表面用 renderer-neutral `PresentationReceipt`。

---

## 明确废止的口径

施工与测试不得再当验收：

1. 练习页对任意 scope 同时提供错题 / 单词 / 语法 / Anki 四队列，以及智能开始跨课种跳转。
2. 导入 Anki 卡答错写入错题本，再从错题复习重放。
3. 每题提交即 introduced，导致未完成课的卡进入 Anki 复习。
4. 第一遍下课或课内客观题写入 Official Again/Good（与方案 A 冲突；与 Anki 复习首次评分双写）。
5. 2026-08-29 第一次修订的「新卡不必上课、introduced 不得过滤正式队列」。
6. 以 `courseGradesScheduler` 默认关为由，把遗忘写进错题本。第一遍可以不评分；一旦评分，只进官方。

---

## 后果

- 练习页 / 个人页 / Hero 必须按 scope 换入口；只藏格子但全局错题本仍混写，视为未落地。
- `LessonViewModel` 对 Anki-owned 交互：`recordMistakes: false`，不 `registerWord`；`markIntroduced` 挪到 `_onLessonCompleted`（该课全部 cardId 一次）。存量 Anki 错题按卸载同类规则清理。
- 导入历史解锁继续走既有 `ImportedHistoryIntroducer` / `seedOfficialProjection`（`reps ≥ 1`）。
- 重做提前复习是新施工：官方 queue 对非到期卡打分；未落地前不得用错题本或 Turna FSRS 冒充。
- `OfficialAnkiHomeDueSync` / `getReviewQueue` 协议错误（过限 `fetchLimit`、把 `QUEUE_EMPTY` 当整次刷新失败）必须修，否则解锁后 Anki 入口仍是「—」。
- 非 Android 上 Anki scope 展示不可用，不回退语言三队列。
- [`docs/anki-course-review-unification-plan.md`](../anki-course-review-unification-plan.md) 的「P0–P10 已落地」不覆盖本修订。实现另开施工，不在本 ADR 排期。

---

## 仍有效的落地约束（2026-08-21）

- 正式复习入口一律经 `FormalReviewLauncher`；Official 不可用 fail-closed。
- 新导入 Official-first：不写 Turna Anki SRS；同 hash 再导入 no-op。
- 旧数据 census / owner 回填 / 投影不把 Turna 历史重放到 Official。
- 产品统计按 `eventId` 去重；`loading` / `unavailable` / `error` / `stale` 与 0 可区分。
- 正式路径不运行时二次 classify。

---

## 历史摘要（已非现行）

- **2026-08-20：** 同一张卡一个身份；正式复习 `due ∩ placement ∩ introduced`；课程决定是否已学。实现上每题 introduced、课内记错题、不写官方，导致「做错只进错题、Anki 复习进不去」。
- **2026-08-29 第一次：** 切开练习队列，并一度废止 introduced 门槛。同日第二次修订收回该门槛，改为「Lesson 完成或导入历史 = 已解锁」，第一遍不写 scheduler。
