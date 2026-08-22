# Turna 语言课程 Playground 实施计划

> 状态：待实施  
> 日期：2026-08-22  
> 范围：练习 Hub 顶部「快速练习」、语言课程 Playground 首页、自由练习题库组装、练习会话、结果页、统计与测试  
> 硬约束：**Playground 只属于语言学习课程；当前课程为传统 Anki 或 Official Anki 时不得显示、不得通过路由进入、不得读取任何 Anki 题目。**

## 0. 结论先行

把练习 Hub 顶部现有的「快速练习」从“单击后直接进入单词配对”改为「Playground / 自由练习场」入口。入口点击后打开独立页面，让学习者选择内容范围、练习时长、难度、答题方向和题型，也可以直接启动默认的「智能开练」。

Playground 与正式复习的职责必须分开：

```text
语言课程
  -> 练习 Hub 显示 Playground Hero
  -> Playground 只读取当前语言课程内容
  -> 自由选择 / 智能混合 / 每日挑战
  -> 错误可进入错题记录，完成可进入学习统计
  -> 不改变正式 SRS 到期时间

Anki / Official Anki 课程
  -> 练习 Hub 不渲染 Playground Hero 及其占位间距
  -> 深链或历史路由进入时拦截并返回
  -> 继续使用现有 Anki 复习入口和正式调度
```

首版优先提供可以复用现有领域模型和 renderer 的模式：智能混合、单词配对、极速选择、听音辨义、听写挑战、句子拼图、填空冲刺和每日混合。翻译挑战放到第二阶段；发音评分在具备可靠的录音、语音识别和评分链路前不进入范围。

## 1. 当前基线

### 1.1 已有实现

| 能力 | 当前实现 | 本轮处置 |
| --- | --- | --- |
| 快速练习入口 | `PlayHubScreen` 顶部 `QuickPlayHero` | 改名为 Playground，跳转独立页面 |
| 单词配对 | `MatchWordsPage` + `MatchProvider` | 保留玩法，改为注入当前课程词对 |
| 每日挑战 | `DailyChallengePage` + `DailyChallengeAssembler` | 纳入 Playground，修正数据范围和 Anki 默认值 |
| 题目渲染 | `InteractionRenderer` 注册表 | 复用，不复制各题型 UI |
| 合成课程会话 | `LessonViewModel.loadLessonInstance` | 作为混合练习的会话内核 |
| 错题记录 | `MistakeProvider` + `LessonViewModel` | Playground 客观错题继续记录 |
| 课程作用域 | `CourseProvider.courseScope` | 当前用 `anki:` 前缀识别 Anki；预留显式课程类型 |
| 学习统计 | `StudyLogRepository` / `StudyActivityType` | 增加 Playground 独立活动类型 |

### 1.2 当前问题

1. `QuickPlayHero.onTap` 直接打开 `MatchWordsRoute`，所谓“快速练习”实际上只有一个模式。
2. `MatchProvider.initializeGame()` 固定读取 `allLevel1Words`，没有使用当前课程、当前单元或学习进度。
3. `DailyChallengeAssembler` 默认 `includeAnki = true`，而且读取 scope-independent 的 `allSections`，不能原样作为语言 Playground 数据源。
4. `CourseProvider` 只预载当前第一个 Section，其余 Section 是 shell；“整个课程”范围必须先显式加载符合条件的语言 Section。
5. 语言题型和 Anki 卡片共用 `Interaction` 联合类型，组装器必须显式拒绝 `AnkiCard`、`AnkiHtmlCard`，不能只依赖入口隐藏。
6. `HomePage` 使用 `IndexedStack` 保留 Play Hub；切换课程后必须通过 `context.select<CourseProvider, ...>` 触发入口显隐更新。

## 2. 产品目标与非目标

### 2.1 产品目标

- 把单一玩法升级为语言课程的自由练习入口。
- 默认一点击即可开始，同时允许用户进行轻量定制。
- 所有练习内容来自当前语言课程，且能够追溯到真实课程题目或词条。
- 复用现有 `Interaction`、renderer、音频和答题反馈，避免形成第二套题目系统。
- Playground 错题可以帮助后续学习，但不会扰乱正式 SRS 调度。
- 内容不足、音频缺失或某题型不可用时可以平稳降级。
- 保持现有复习中心、AI 助手、词典和 Anki 复习入口职责不变。

### 2.2 非目标

- 不把 Playground 做成第二套课程树。
- 不在本轮改造 Anki 正式复习体验或 Anki scheduler。
- 不允许将 Anki 卡片“转成语言题”后偷偷进入 Playground。
- 不在首版提供联网对战、排行榜或社交挑战。
- 不在首版提供 AI 实时出题；首版应完全离线可用。
- 不在没有可靠语音评分能力时宣传“发音打分”。
- 不把 AI 助手、词典、错题复习和 SRS 复习搬进 Playground。

## 3. 不再摇摆的产品决策

1. 练习 Hub 只保留一张 Playground Hero；完整模式列表放在独立页面，避免 Hub 继续变长。
2. 默认主按钮为「智能开练」，推荐配置为 3 分钟、标准难度、双向随机、智能混合。
3. Playground 入口只在当前课程为语言课程时显示；Anki scope 下 Hero 与其下方间距一起消失。
4. Playground 页面本身再次检查资格；不依赖“用户看不到入口”作为安全边界。
5. 题库采用正向语言白名单与 Anki 黑名单双重约束：Section 必须是语言 Section，Interaction 还必须不是 Anki 卡片类型。
6. 自由练习不调用正式 SRS 的 `review()`、`rate()` 或 due-date 更新路径。
7. 客观题答错继续写入 `MistakeProvider`；自评或无标准答案的题不制造错题。
8. 每次完成会话只写一条 Playground 学习日志；中途退出不发完整完成奖励。
9. XP 奖励按“有效完成题数”计算并设置单会话上限，不能让无限模式成为无上限刷 XP 通道。
10. 随机组装在测试中必须可注入 `Random`，同一 seed 产生稳定结果。
11. 当前版本可用 `courseScope.startsWith('anki:')` 识别 Anki；增加其他语言课程 scope 时必须升级为显式 `CourseKind`，不能把“非内置课程”默认等同于 Anki。

## 4. 信息架构与页面设计

### 4.1 练习 Hub 入口

用 Playground Hero 替换当前 Quick Play Hero：

```text
┌──────────────────────────────────┐
│  🎮  Playground                  │
│      自由组合题型，随时练几分钟     │
│                         开始探索 → │
└──────────────────────────────────┘
```

建议文案：

- 标题：`Playground`
- 中文辅助名：`自由练习场`
- 副标题：`自由组合题型，随时练几分钟`
- 图标：`Icons.sports_esports_rounded` 或 `Icons.extension_rounded`

Hero 继续沿用现有 teal → sky 渐变、圆角和暗色适配。组件可从 `QuickPlayHero` 重命名为语义更中立的 `PlaygroundHero`；若 AI 页仍复用该组件，则改为 `GradientActionHero`，避免把业务名写进通用组件。

### 4.2 Playground 首页

```text
AppBar: Playground

┌──────────────────────────────────┐
│ 智能开练                          │
│ 3 分钟 · 标准 · 智能混合           │
│                         立即开始 → │
└──────────────────────────────────┘

练什么
[最近学习] [当前单元] [整个课程] [薄弱内容]

练习模式
[单词配对] [极速选择]
[听音辨义] [听写挑战]
[句子拼图] [填空冲刺]

今天的挑战
[每日混合 · 15 题]

上次练习
正确率 86% · 3 分 12 秒              [再来一次]
```

交互原则：

- 首页首屏必须始终能看到「智能开练」按钮。
- 不要求用户先配置才能开始；配置项使用上次选择或默认值。
- 不可用模式显示原因，例如“当前范围没有音频题”，而不是点击后进入空页面。
- “最近学习”和“薄弱内容”没有足够数据时自动回退到当前单元，并在开始前用轻提示说明。
- 支持系统字体缩放；题型网格在窄屏或大字体下允许变成单列。

### 4.3 会话配置

首版配置控制在一屏内：

| 维度 | 选项 | 默认值 |
| --- | --- | --- |
| 内容范围 | 最近学习、当前单元、整个语言课程、薄弱内容 | 最近学习；无数据时当前单元 |
| 时长 | 1 分钟、3 分钟、5 分钟、无限 | 3 分钟 |
| 难度 | 轻松、标准、挑战 | 标准 |
| 答题方向 | 目标语→母语、母语→目标语、随机 | 随机 |
| 题型 | 智能混合或手动多选 | 智能混合 |
| 音效 | 开 / 关 | 跟随现有设置 |

题数由时长估算，但在启动前固化为会话配置，避免设备性能差异导致完全不同的题量。建议初始映射为 1 分钟 5 题、3 分钟 10 题、5 分钟 15 题；无限模式按批次补题。

### 4.4 结果页

结果页至少显示：

- 正确题数、错误题数、正确率、总用时。
- 最长连击与平均每题耗时。
- 各题型表现，指出本次最薄弱类型。
- 新增错题数量。
- 获得的 XP；达到上限时不隐藏上限规则。
- 「再来一次」「只练错题」「返回 Playground」三个动作。

## 5. 练习模式目录

| 模式 | 内容来源 / 现有能力 | 首版策略 | 阶段 |
| --- | --- | --- | --- |
| 智能混合 | 所有支持的语言 `Interaction` | 根据可用内容、近期错题和连续重复限制分配题型 | P2 |
| 单词配对 | `ShowWord` 引用的 `WordEntry` | 把当前固定词表改为当前课程词对注入 | P2 |
| 极速选择 | `MultipleChoice`、`ReadingMcq` | 复用现有 renderer，限时连续作答 | P2 |
| 听音辨义 | `ListenAndPick` 或有音频/TTS 的词条 | 缺少音频时允许 TTS；完全不可播放则不入池 | P2 |
| 听写挑战 | `TypeTheWord` 或可生成的词条听写 | 统一大小写、首尾空格和语言标点规范 | P2 |
| 句子拼图 | `ReorderSentence` | 直接复用 renderer | P2 |
| 填空冲刺 | `FillBlank` | 直接复用 renderer | P2 |
| 每日混合 | `DailyChallengeAssembler` | 固定 15 题、按本地日期生成稳定 seed、强制排除 Anki | P3 |
| 翻译挑战 | `TranslateSentence`、`ReadingShortAnswer` | 先建立宽松判分与可接受答案规则 | P4 |
| 语法工坊 | 带 `grammarPointId` 的题目 | 按语法点筛选，不替代正式语法复习 | P4 |
| 跟读练习 | TTS + 未来语音识别 | 具备录音权限、离线/隐私策略和可靠评分后再做 | 暂缓 |

### 5.1 智能混合规则

首版采用可解释的规则，不引入 AI：

1. 优先从用户选择的内容范围取题。
2. 若选择“薄弱内容”，以错题快照和词条 ID 为主要来源。
3. 同一种题型连续最多出现 2 次。
4. 同一词条或同一原题在一个有限会话中最多出现 1 次；“只练错题”允许一次重试。
5. 有听力内容时，混合会话至少包含 20% 听力题；用户关闭音效时自动取消此约束。
6. 内容不足时缩短题量，不使用与当前课程无关的固定题库填充。
7. 选择“挑战”难度时优先自由输入、反向题和句子题；“轻松”优先选择题和配对。

## 6. 课程资格与 Anki 隔离

### 6.1 当前版本资格判断

新增单一权威策略，例如：

```dart
abstract final class LanguagePlaygroundEligibility {
  static bool isEligibleScope(String courseScope) =>
      !courseScope.startsWith('anki:');
}
```

所有调用点使用同一策略，不在 Widget、assembler 和 route 中各写一份字符串判断。

当前课程模型只有内置语言课程 scope `''` 与 Anki scope `anki:<importId>`，所以上述判断足以落地。但这是过渡策略。未来支持多个语言课程时，应把课程条目升级为：

```dart
enum CourseKind { language, anki, officialAnki }
```

之后资格判断改为 `course.kind == CourseKind.language`，避免 scope 编码继续承担业务类型职责。

### 6.2 三层隔离

#### 第一层：入口可见性

`PlayHubScreen` 通过 `context.select<CourseProvider, bool>` 监听资格：

- 语言课程：渲染 Playground Hero + 24px 间距。
- Anki 课程：Hero 和专属间距都不创建，下一分区自然上移。

#### 第二层：页面入口保护

`LanguagePlaygroundPage` 在进入与课程切换后检查资格：

- 不合格时不启动任何题库加载。
- 显示一次简短提示后 `maybePop()`；若没有可返回页面，则切回练习 Hub。
- route 保留 `CourseReadyGuard`，资格判断由页面或新增的小型 guard 负责。

#### 第三层：数据过滤

`PlaygroundAssembler` 必须满足：

- 只读取 `CourseProvider.sections` 对应的当前 scope，不读取 `allSections`。
- Section level 为 `Anki` 或 `OfficialAnki` 时直接拒绝。
- `AnkiCard`、`AnkiHtmlCard` 永不加入候选池。
- 从错题快照恢复题目时再次执行同一类型过滤。
- 即使调用者错误地传入 Anki scope，也返回明确的 `ineligibleCourse` 结果，而不是空白 `Lesson`。

这三层均需要独立测试，防止以后入口重构或深链绕过产品边界。

## 7. 数据来源与组装架构

### 7.1 建议领域模型

```dart
enum PlaygroundMode {
  smartMix,
  wordMatch,
  quickChoice,
  listenAndPick,
  dictation,
  sentenceOrder,
  fillBlank,
  dailyMix,
  translation,
}

enum PlaygroundContentScope {
  recent,
  currentUnit,
  wholeCourse,
  weak,
}

enum PlaygroundDifficulty { easy, standard, challenge }

enum PlaygroundDirection {
  targetToNative,
  nativeToTarget,
  mixed,
}

class PlaygroundSessionConfig {
  final PlaygroundMode mode;
  final PlaygroundContentScope contentScope;
  final PlaygroundDifficulty difficulty;
  final PlaygroundDirection direction;
  final int targetQuestionCount;
  final bool endless;
  final bool audioEnabled;
}
```

组装返回值不要只返回 `Lesson?`，应带上可解释状态：

```dart
sealed class PlaygroundAssemblyResult {}

class PlaygroundReady extends PlaygroundAssemblyResult {
  final Lesson lesson;
  final PlaygroundSessionMetadata metadata;
}

class PlaygroundUnavailable extends PlaygroundAssemblyResult {
  final PlaygroundUnavailableReason reason;
  final Set<PlaygroundMode> availableAlternatives;
}
```

典型不可用原因包括：`ineligibleCourse`、`noCourseContent`、`noItemsForMode`、`sectionLoadFailed` 和 `audioUnavailable`。

### 7.2 内容加载

`CourseProvider.load()` 只预载第一个 Section，因此各范围采用不同加载策略：

- 当前单元：保证 `currentSectionId` 已加载，只扫描 `currentUnit`。
- 最近学习：从完成记录取得 lesson ID，再通过 `CourseLoader.loadLessonById` 按需加载。
- 整个课程：筛出当前 scope 的语言 Section ID，再调用 `ensureSectionLoaded`；使用有限并发，失败 Section 可跳过但要记录诊断。
- 薄弱内容：优先使用 `MistakeProvider` 的 frozen interaction；缺失时用词条 ID 回查语言词库。

不得为了补足题量回退到 `allLevel1Words` 或其他课程的内容。

### 7.3 词对来源

单词配对不能继续读取全局固定 `allLevel1Words`。建议从所选范围内的 `ShowWord.wordId` 收集稳定 ID，再到 `vocabById` 或课程仓库解析 `term/translation`：

```text
选中的 Section / Unit / Lesson
  -> 收集 ShowWord.wordId
  -> 解析当前课程 WordEntry
  -> 去重并排除空 term/translation
  -> 按 session seed 洗牌
  -> 注入页面级 Match controller
```

若不足 4 对，单词配对模式标记为不可用，并推荐极速选择或智能混合，不使用外部固定词表填充。

### 7.4 题目转换原则

- 已有目标题型的 authored interaction 直接复用，不做无意义转换。
- 从 `WordEntry` 生成选择题时，干扰项必须来自同一课程和相近内容范围。
- 每个生成题保存 `sourceWordId`、`sourceLessonId` 和生成规则，方便错题归因和统计。
- 生成 interaction 的 ID 使用会话 ID + 来源 ID + 序号，保证一次会话内唯一。
- 所有转换函数保持纯函数并接受 `Random`，便于单元测试。
- 任何转换器都不接受 Anki interaction 作为输入。

## 8. 会话执行与学习语义

### 8.1 复用现有能力

混合题型会话继续使用：

- `LessonViewModel.loadLessonInstance()` 管理当前题、提交、进度与结果。
- `InteractionRenderer` 注册表渲染选择、填空、听力、听写、排序和翻译。
- `LessonCheckButton`、进度条、音效与无障碍组件保持一致。
- `MistakeProvider` 记录客观错误。

建议抽取通用 `SyntheticPracticeSessionScaffold`，让 Playground、Daily Challenge 和 Weak Words 共享：

- AppBar 与关闭确认。
- 进度与计时。
- renderer 分发。
- auto-advance。
- 完成结果收集。

不要一次性重写三个页面。先从 Daily Challenge 中抽出最小公共骨架，确认测试稳定后再迁 Weak Words。

### 8.2 SRS 与错题合同

| 行为 | Playground 是否执行 |
| --- | --- |
| 写正式 SRS rating | 否 |
| 修改 due date / interval | 否 |
| 注册新的正式 SRS 项 | 否 |
| 记录客观错题 | 是 |
| 错题答对后自动删除历史错题 | 否；由错题复习负责 |
| 写学习时长与正确率 | 完成会话时写一次 |
| 发 XP | 是，按有效完成题数且有上限 |
| 发完美会话奖励 | 可选，首版只保留小额固定奖励 |

如果直接复用 `LessonViewModel` 会触发 SRS 注册或更新，应新增明确的 session policy，而不是在各个调用点零散跳过：

```dart
class PracticeSessionPolicy {
  final bool recordMistakes;
  final bool registerSrsItems;
  final bool updateSrsSchedule;
  final bool grantRewards;
}
```

Playground policy 固定为 `recordMistakes: true`、`registerSrsItems: false`、`updateSrsSchedule: false`。

### 8.3 学习日志

为 `StudyActivityType` 增加 `playgroundPractice`，完成一次会话写入：

- session ID 与时间。
- 实际完成题数，而不是目标题数。
- 正确、错误、跳过数量。
- 时长与 XP。
- 去重后的语言 `wordIds`。
- 模式与内容范围可作为扩展 metadata；若当前 `StudyLog` 不支持 metadata，首版只增加类型，不把配置塞进 `lessonId`。

无限模式每完成一个批次可以写 checkpoint，但最终只发一次会话完成奖励，避免重复入账。

## 9. 文件与模块变更建议

### 9.1 新增文件

```text
lib/application/playground/
  language_playground_eligibility.dart
  playground_models.dart
  playground_content_source.dart
  playground_assembler.dart
  playground_session_controller.dart

lib/views/playground/
  language_playground_page.dart
  playground_session_page.dart
  playground_result_page.dart
  components/
    playground_quick_start_card.dart
    playground_mode_grid.dart
    playground_config_sheet.dart
    playground_result_summary.dart
```

如抽取通用合成练习容器：

```text
lib/views/practice/components/
  synthetic_practice_session_scaffold.dart
```

### 9.2 修改文件

| 文件 | 变更 |
| --- | --- |
| `lib/views/play/play_hub_screen.dart` | 监听课程资格；替换 Hero 文案和路由；Anki 时不渲染入口及间距 |
| `lib/views/play/components/play_tiles.dart` | 将 `QuickPlayHero` 重命名为业务中立组件或新增 Playground Hero |
| `lib/application/match_provider.dart` | 移除固定词表依赖，或由新的页面级 match controller 取代 |
| `lib/views/play/match_words.dart` | 接受已解析的 session config / 词对来源 |
| `lib/application/daily_challenge_assembler.dart` | 默认排除 Anki；改用当前语言 scope；保留纯采样函数 |
| `lib/views/play/daily_challenge_screen.dart` | 从 Playground 启动；复用通用会话骨架 |
| `lib/application/lesson_viewmodel.dart` | 增加合成练习 session policy，显式关闭 SRS 变更 |
| `lib/domain/study/study_log.dart` | 增加 `playgroundPractice` 活动类型 |
| `lib/l10n/app_strings.dart` | 增加 Playground、模式、配置、空态和结果文案 |
| `lib/routing/routing.dart` | 注册 Playground 首页、会话和结果 route |
| `lib/routing/routing.gr.dart` | 通过项目既有生成流程更新，不手工维护 |

测试目录建议对应生产目录建立 `test/application/playground/` 与 `test/views/playground/`。

## 10. 分阶段实施

### P0：资格策略与产品边界

目标：先让“语言可见、Anki 不可见”成为可测试合同。

- 新增 `LanguagePlaygroundEligibility`。
- `PlayHubScreen` 监听 `CourseProvider.courseScope`。
- 将 Hero 标题和副标题改为 Playground。
- 新增空的 Playground 页面与 route，页面执行二次资格检查。
- 更新 Play Hub widget tests。

完成标准：

- scope `''` 时入口存在且可打开。
- scope `anki:<id>` 时入口、文案、点击目标和专属间距均不存在。
- 已打开 Playground 后切换为 Anki scope，不会继续加载或开始练习。

### P1：数据源与配置模型

目标：建立只读取当前语言课程的可复用题库管线。

- 新增 session config、mode、scope、difficulty、direction 模型。
- 实现当前单元、整个课程、薄弱内容的内容来源。
- 最近学习范围若缺乏可靠 lesson ID 记录，可在 P1 先回退当前单元，P3 再补全。
- 加入 Section level 和 Interaction 类型双重 Anki 过滤。
- 实现确定性去重、洗牌、题量裁剪与不可用原因。

完成标准：

- 任意输入下都不会返回 `AnkiCard` 或 `AnkiHtmlCard`。
- 整个课程只包含当前语言 scope。
- Section 加载失败时返回可解释状态，不抛到空白页。

### P2：首版玩法与统一会话

目标：交付可用的 Playground MVP。

- 完成 Playground 首页、智能开练和配置 sheet。
- 接入极速选择、听音辨义、听写、句子拼图、填空。
- 把单词配对改为当前课程词对注入。
- 建立通用合成练习会话骨架。
- 完成结果页、再来一次和只练错题。
- 接入 Playground session policy，确认不修改 SRS。

完成标准：

- 六种首版模式在有内容时可完成一轮。
- 内容不足模式显示禁用原因。
- 完成与退出路径没有计时器、音频或 provider 泄漏。

### P3：每日混合、统计与奖励

目标：把已有 Daily Challenge 正式纳入 Playground，并补齐持久化。

- Daily Challenge 改为只读当前语言课程并强制排除 Anki。
- 按本地日期 + course ID 生成每日稳定 seed。
- 增加 `StudyActivityType.playgroundPractice`。
- 保存上次配置、上次结果和模式最佳成绩。
- 定义 XP 公式、单会话上限与无限模式 checkpoint。
- 接入成就系统时只记录实际完成题数，不把目标题数算作完成。

完成标准：

- 同一天、同一课程的每日题组顺序稳定。
- 完成会话只写一条主学习日志和一次奖励。
- 正式 SRS 状态前后完全一致。

### P4：增强模式与体验打磨

目标：在首版数据证明有使用价值后扩展深度。

- 增加宽松判分的翻译挑战。
- 增加按 `grammarPointId` 筛选的语法工坊。
- 完善“最近学习”的课程进度映射。
- 增加模式表现趋势，而不是只显示历史最高分。
- 根据真实内容可用率调整智能混合权重。
- 评估语音识别、录音权限、隐私和离线策略后再决定跟读评分。

## 11. 测试计划

### 11.1 单元测试

- `LanguagePlaygroundEligibility`：语言、传统 Anki、Official Anki scope。
- `PlaygroundAssembler`：每个内容范围和每个模式的正确过滤。
- Anki Section 双过滤与 Anki Interaction 双过滤。
- 错题快照中混入 Anki 卡片时仍被拒绝。
- 相同 seed 结果稳定，不同 seed 允许变化。
- 去重、题量不足、空内容、Section 加载失败。
- 难度与答题方向映射。
- 单词配对只使用当前课程的 `WordEntry`。
- session policy 不注册、不更新 SRS。
- XP 上限和无限模式幂等入账。

### 11.2 Widget 测试

- 语言课程下 Play Hub 显示 Playground；Anki scope 下完全不显示。
- 切换 course scope 后，`IndexedStack` 中保留的 Play Hub 正确重建。
- Hero 点击进入 Playground 首页，不再直接进入 Match Words。
- 深链进入时遇到 Anki scope 会安全返回。
- Playground 首页在小屏、大字体、暗色和高对比模式下无溢出。
- 不可用模式有禁用语义和可读原因。
- 配置 sheet 保存并恢复上次选择。
- 每种 renderer 的提交、继续、自动前进与完成。
- 中途退出确认、计时器停止与音频停止。
- 结果页按钮和“只练错题”题组。

### 11.3 集成与回归测试

- 语言 → Anki → 语言课程切换后入口和配置恢复正确。
- 传统 Anki 与 Official Anki 均无法污染候选池。
- Playground 会话前后对比 SRS state、due count 和 interval 无变化。
- 错误答案只产生预期的错题记录，不产生重复快照。
- 学习日志、XP、成就事件各写一次。
- 现有 Match Words、Daily Challenge、Weak Words、Play Hub、复习中心测试继续通过。
- `flutter analyze` 无新增问题，非 golden 全量测试通过；视觉改动补充 light/dark golden。

## 12. 可观测性与隐私

建议记录不包含实际课程文本的产品事件：

- Playground Hero 展示与点击。
- session 开始、完成、退出。
- mode、content scope、difficulty、目标题数与实际题数。
- 正确率、时长、内容不足原因。
- 因课程不合格而拦截的入口次数。

不得上传用户作答原文、课程原文、Anki 卡面 HTML 或音频内容。自由输入题仅在本地用于判分和错题快照。

## 13. 风险与应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 只隐藏 Hero，深链仍可进入 | Anki 边界失效 | 入口、页面、assembler 三层隔离 |
| `allSections` 混入其他课程 | 练到不属于当前课程的内容 | 只读当前 scope 的 `sections`，正向筛语言 Section |
| 未加载 Section 导致题库偏少 | “整个课程”实际只取首章 | 启动前显式加载目标 Section，并显示加载/错误态 |
| 固定 `allLevel1Words` 残留 | 自定义课程练到土耳其固定词表 | Match 数据必须由 session 注入；不足时禁用 |
| 复用 LessonViewModel 意外更新 SRS | 自由练习破坏记忆曲线 | 引入显式 session policy，并做状态前后对比测试 |
| 题型很多但单门课内容不足 | 大量空模式 | 首页按候选数量预计算 availability，智能降级 |
| 无限模式刷 XP | 经济系统失衡 | 按有效答题发放、单会话上限、幂等 receipt |
| 多个 synthetic 页面重复代码 | 行为逐渐漂移 | 抽最小通用 session scaffold，分步迁移 |
| 未来新增语言 course scope | 前缀判断难维护 | 后续升级显式 `CourseKind` |

## 14. 验收清单

### 产品验收

- [ ] 语言课程练习 Hub 顶部显示 Playground Hero。
- [ ] Hero 点击进入独立 Playground 首页，不再直接进入单词配对。
- [ ] Anki 与 Official Anki 课程不显示 Hero，也不留下空白间距。
- [ ] Anki scope 无法通过深链、返回栈或课程切换继续使用 Playground。
- [ ] 智能开练无需配置即可开始。
- [ ] 首版六种模式和每日混合在内容存在时可正常完成。
- [ ] 模式不可用时给出具体原因和可用替代项。
- [ ] 结果页显示正确率、用时、连击、薄弱题型、新增错题和 XP。

### 数据验收

- [ ] Playground 候选池中不存在任何传统或 Official Anki 内容。
- [ ] 单词配对不再读取与当前课程无关的固定词表。
- [ ] Playground 前后 SRS due、interval、rating 和队列数量不变。
- [ ] 客观错题正确写入，重复提交不会重复记账。
- [ ] 一次完成只产生一条主学习日志和一次奖励 receipt。
- [ ] 整个课程范围确实覆盖所有成功加载的语言 Section。

### 工程验收

- [ ] 新增领域逻辑有单元测试，随机逻辑可固定 seed。
- [ ] Play Hub、路由保护、配置与结果页有 widget tests。
- [ ] light/dark、高对比、大字体和小屏布局通过视觉检查。
- [ ] `flutter analyze` 无新增 error/warning。
- [ ] `flutter test --exclude-tags golden` 全绿。
- [ ] 相关 golden 测试更新且人工检查通过。

## 15. 推荐首个施工切片

为了尽早固化最重要的边界，第一份 PR 只完成以下内容：

1. 新增 `LanguagePlaygroundEligibility` 及单元测试。
2. 将 Play Hub Hero 文案改为 Playground，并改为独立 route。
3. 语言 scope 显示、Anki scope 隐藏 Hero 与间距。
4. 新增 Playground 首页骨架，只实现「智能开练」占位和模式 availability 占位。
5. 页面执行二次资格检查。
6. 增加 Play Hub 在语言/Anki/课程切换三种状态下的 widget tests。

该切片不触碰 Match、Daily Challenge、SRS 或奖励逻辑，合并后即可保证产品入口和 Anki 隔离方向不会在后续施工中反复变化。
