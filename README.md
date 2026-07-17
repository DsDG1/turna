# Varnamala Plus

> 本地优先、离线的 Flutter 语言学习框架。当前目标语：**Turkish（土耳其语）**。

[![Flutter CI](https://github.com/rshrc/Varnamala/actions/workflows/flutter_ci.yml/badge.svg)](.github/workflows/flutter_ci.yml)

---

## 这是什么

基于上游 [Varnamala](https://github.com/rshrc/Varnamala) 的 Section/Unit/Lesson/SRS/错题本骨架，聚焦 **Turkish**，持续精简与深化。

- **纯本地**：SQLite（drift），无云后端/推送/登录。
- **单人离线**：无好友、排行榜、联赛、心数、宝石。
- **AI 辅助开发**：工程决策记录在 `docs/decisions/`。

> 本仓库非上游官方版本；纯原版功能请访问 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)。

---

## 语言学习理念与教学法基础

本项目的课程设计与复习机制建立在下述二语习得（Second Language Acquisition, SLA）与认知心理学研究的基础上。以下简要介绍贯穿全文的核心概念。

### 可理解输入与 i+1 原则

Stephen Krashen 的**输入假说**（Input Hypothesis）认为，语言习得发生在学习者接触到略高于当前水平的**可理解输入**（comprehensible input）时——即 "i+1"，其中 i 为学习者当前水平。本项目的 CEFR 分级 Section（A1→B2）与 inter-section 前置依赖即是对这一原则的工程化实现：学习者必须在较低等级的课程中达到一定掌握程度后，才能解锁下一等级的内容。

### 间隔重复与遗忘曲线

Hermann Ebbinghaus 在 1885 年描述了**遗忘曲线**（forgetting curve）：新记忆在形成后迅速衰减，但每次**主动检索**（active retrieval）都能显著减缓衰减速度。**间隔重复**（spaced repetition）将复习安排在遗忘临界点附近，以最少的复习次数达成最长的记忆保持。这在词汇习得中被认为是实证基础最牢固的策略之一（Nation, 2013）。

本项目的 SRS 引擎采用 **SM-2 算法**（SuperMemo 2），根据每次复习的自我评分动态调整下次复习间隔。详见下方「复习与练习」节。

### 检索练习与测试效应

**测试效应**（testing effect）指：相对于被动重读，主动从记忆中提取信息（即"自我测试"）能显著增强长期记忆保持（Roediger & Karpicke, 2006）。本项目的填空、翻译、听写、选择等多种题型本质上都是不同形式的检索练习，而非单纯的"考核"。

### 多技能整合

应用语言学将语言能力分解为**接受性技能**（听、读）与**产出性技能**（说、写），以及词汇、语法、语音等**语言知识**维度。本项目的 6 种 Lesson Template（intro / practice / listening / reading / review / mastery）与 13 种 Interaction 题型覆盖了从词汇呈现到听读输入再到可控产出的完整学习闭环，避免孤立地训练单一技能。

### 关于土耳其语

Turkish 属于**突厥语系**，是一种**黏着语**（agglutinative language）：语法关系通过向词根依次附加词缀来表达，一个词可以承载相当于英语一整句的信息（如 *evlerinizdekilerden* = "from those at your houses"）。其核心特征包括：

- **元音和谐**（vowel harmony）：词缀的元音必须与词根元音在舌位前后与唇形圆展上保持一致。
- **SOV 语序**：主语—宾语—动词，与汉语（SVO）和英语（SVO）语序显著不同。
- **无语法性别**：无冠词、无名词类别，代词无性别区分。

这些特征使 Turkish 对于以汉语为母语的学习者既有门槛（语序差异、黏着形态），也有便利（无性别、拼读规则高度一致）。本项目针对这些特点设计了渐进式的语法复习流程与丰富的词形变化练习。

---

## 快速开始

```bash
git clone git@gitee.com:dhwdwf3/Varnamalaplus.git
cd Varnamalaplus
flutter pub get
flutter run
```

> **生成代码已提交到版本库**（`.freezed.dart` / `.g.dart` / `.gr.dart` / `.gen.dart` / `injection.config.dart`），因此**新克隆无需先跑 `build_runner`**。只有当你修改了带 `@freezed`、`@JsonSerializable`、`@AutoRoute`、`@injectable` 注解的类时，才需要重新生成：
>
> ```bash
> flutter pub run build_runner build --delete-conflicting-outputs
> ```

### 当前内容状态

课程为 Turkish（ADR 0020）。8 个 CEFR 分级 Section，覆盖 A1（入门）→ B2（中高级），含 inter-section 前置依赖。

> **CEFR**（Common European Framework of Reference for Languages，欧洲语言共同参考框架）将语言能力分为三等六级：A1/A2（基础使用者）、B1/B2（独立使用者）、C1/C2（熟练使用者）。本项目目前覆盖 A1→B2 四个等级，Section 1（A1）有真实内容，Sections 2–8（A1 高阶→B2）含 AI 生成的占位课程。

清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

---

## 框架已完成的能力

### 课程引擎

- **层级模型**：`Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction`（freezed + JSON 序列化）。
- **13 种 Interaction 题型**（`@injectable` 插件注册到 GetIt），按语言技能维度分类：
  - **词汇呈现**：`showWord`（形式 + 意义 + 音频）
  - **接受性词汇**：`multipleChoice`（识词选义）、`multiSelect`（多选）
  - **产出性词汇/句法**：`fillBlank`（完形填空）、`translateSentence`（翻译）、`reorderSentence`（乱序组句）、`typeTheWord`（听音拼写）
  - **听力**：`listenAndPick`（听后选择）、`listenOnly`（纯听输入）
  - **阅读**：`readingMcq` / `readingTrueFalse` / `readingShortAnswer`（篇章理解）
- **6 种 Lesson Template**，覆盖从词汇呈现到综合产出的完整教学循环：
  - **intro**（认识新词）：通过 `showWord` 呈现目标词汇的形式（拼写/发音）与意义（翻译/图片），配合简单选择题建立初步的形式—意义映射（form-meaning mapping）。
  - **practice**（巩固练习）：在受控语境中反复操练目标语言点——填空、翻译、组句——使陈述性知识（declarative knowledge）开始向程序性技能转化。
  - **listening**（听力训练）：采用 `listenAndPick`、`typeTheWord`、`listenOnly` 等交互方式，训练自下而上（bottom-up）的语音解码能力。`ListeningPhase` 支持 debut→main→fin 三段式音频结构，可叠加 BGM 模拟真实听力环境。
  - **reading**（阅读理解）：通过短文阅读 + `readingMcq`、`readingTrueFalse`、`readingShortAnswer` 三道递进题目，训练自上而下（top-down）的篇章理解策略。
  - **review**（复习）：跨单元回顾近期所学，采用交错出题方式避免集中练习效应。
  - **mastery**（综合测验）：混合题型限时完成，模拟真实语言使用中的多技能并行需求。
  - 另含 `legacy` 兜底模板用于兼容旧版课程数据。`Lesson.flattenedStages` 展平为渲染器可遍历的 `List<Stage>`。
- **按需加载**：`index.json` + per-section JSON + drift SQLite 缓存（schemaVersion 5，含 expressions 表），按内容版本号自动 reseed。

### 复习与练习

- **SRS（间隔重复系统）**：SM-2 算法的单词 + 语法点队列。核心机制如下：
  - 每张闪卡在复习时由学习者自评掌握程度（0–5 级），算法据此计算**下次复习间隔**（从数小时逐步拉长到数月）和 **easiness factor**（易度系数）。
  - 评分为 0–2（失败）时，间隔重置为 1 天并从队列中重新调度；评分 ≥3（通过）时，间隔按 easiness factor 倍增。
  - 这一设计直接对应 Ebbinghaus 遗忘曲线：在遗忘临界点附近安排复习，以最低的总复习次数达成长期记忆保持。间隔重复在二语词汇习得中的效果已在大量实证研究中得到验证（Nation, 2013; Nakata, 2015）。
  - 闪卡显示 "Learned in: <lesson>"，便于学习者回溯初次学习语境。
- **错题本**：30 条 FIFO 队列，保留原始 interaction 快照（含题干、正答、用户错答）。支持重做清除与跳转对应语法点复习。从认知角度看，**错误分析**（error analysis）是 SLA 中理解中介语（interlanguage）发展轨迹的核心手段——学习者的错误并非随机，而是反映了其当前的中介语规则系统（Corder, 1967）。
- **语法复习**：Explain → Practice → Rate 三段流。先呈现语法规则（显性知识输入），再通过练习转化为程序性知识（procedural knowledge），最后自我评估掌握程度。这一流程参考了 **Skill Acquisition Theory**（DeKeyser, 2007）中从陈述性知识到程序性知识的转化路径。
- **每日挑战**：从课程树随机抽取真实题项合成挑战课，实现**间隔交错练习**（interleaved practice）——相比集中练习单一类型，交错练习虽然在训练阶段感觉更吃力，但长期保持效果显著更优（Rohrer & Taylor, 2007）。
- **弱词复习**：近 30 天内错误 ≥2 次的词汇自动汇聚为 10 题迷你 quiz，实现对薄弱项目的**针对性检索练习**。
- **Match Madness**：限时单词配对小游戏，通过速度压力强化词汇的形式—意义连接自动化（automaticity），降低学习者在实际交流中的认知负荷。
- **AI 提示助手**：课程内嵌 AI 聊天面板，按当前题目上下文提供提示与解释，支持 DeepSeek 等 OpenAI-compatible 后端。

### 检索与统计

- **词典/搜索**：搜单词、表达、语法点；`VocabAudioResolver` 播放音频。
- **学习统计仪表盘**：90 天 `StudyLog` + 7 日 XP 趋势 + 时长/准确率/课数/弱词分析。
- **进度导出/导入**：Settings 页支持学习进度 JSON 导出与恢复。
- **课程树加载状态**：显式 `SectionLoadState` + 错误重试 UI。
- **内容更新提示**：检测课程版本变化，提示重置进度。

### 主题与可访问性

- **暗色 / 亮色 / 跟随系统**：`VarnamalaTheme` 语义化颜色 + `ThemeProvider` 持久化。
- **可访问性**：tooltip、MCQ 屏幕阅读语义、对比度感知配色。

### 音频 / TTS

- `AudioController` 统一接管 TTS（`tr`）；Piper 离线模型已移除（ADR 0020）。
- 预录 `audioAsset` 预留给听力练习，支持三段式结构（debut + main + fin）模拟真实听力场景。

**听力教学的语言学考量**：土耳其语的拼写—发音对应高度规则（浅层正字法，shallow orthography），这对初学者的音位意识（phonemic awareness）训练比较友好。然而，其元音和谐系统要求学习者在听力中同时跟踪词根元音的前/后、圆/展特征才能正确预测后续词缀的形态——这构成了从"听到"到"听懂"的关键跨越。`listenOnly` 阶段的纯听输入为学习者提供了专注于音位解码而不受文字干扰的机会，而 `typeTheWord` 阶段则将音位解码与拼写产出结合，双向强化形—音映射。

### 提醒

- **本地每日提醒**：`flutter_local_notifications` + 时间选择器，**无** streak repair。

### 工具与发布

- **发布流水线**：`tool/build_release.py` 一键生成版本化 APK/AAB/web 产物 + 内容清单。
- **内容 CLI**：`tool/course_cli.py`（校验/lint/CSV 导入导出/音频清单/diff）、`tool/export_content_inventory.py`、`tool/split_course.py`。
- **GUI 课程编辑器**：完整 PySide6 桌面编辑器，含教材导入、AI 生成、Workshop 工作区、Git 课程库、操作日志（见下方专节）。
- **app 内置 AI 生成器**：实验性页面 `AiCourseGeneratorPage`，配置任意 OpenAI-compatible endpoint（配置仅存内存）。

---

## 已明确不做

以下"游戏化"机制的移除是经过考量的教学法决策，而非单纯的工程简化：

- ❌ **League/天梯/好友/排行榜/分享**。社会比较（social comparison）虽然在短期能提升参与度，但对语言习得的内在动机（intrinsic motivation）存在抑制作用（Deci & Ryan, 1985 的自我决定理论）。本项目选择以内容驱动而非竞争驱动的学习体验。
- ❌ **Hearts/Streak Repair/商店道具**。惩罚机制（答错扣心）与"失败恐惧"（fear of failure）相关，可能导致学习者回避高难度内容——而高难度内容恰恰是 i+1 原则所要求的习得关键区间。
- ❌ **Speaking 录音匹配**。自动语音评分技术在非主流语种（包括 Turkish）上的可靠性与效度不足，且本项目以 TTS + 听力路径覆盖语音层面的输入训练。
- ❌ **云端 CMS/Firebase/推送通知**。本地优先架构保证了离线可用性与数据隐私，同时避免了服务端依赖带来的持续维护成本。
- ❌ **GUI 替代 JSON 作为真理源**。GUI 编辑器是 JSON 的可视化前端——JSON 始终是课程内容的唯一权威存储格式，确保可版本化、可 diff、可脚本批处理。

---

## 架构

Clean architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route。

```
lib/
├── application/   # Providers：SRS / Grammar / Mistake / StudyStats / Score /
│                  # Streak / Progress / Milestone / Game(facade) / WeakWord /
│                  # DailyChallenge / AiCourse / Audio / Dictionary / Theme …
├── core/          # enums, sm2, spacing, streak_resolver, logger, text_styles
├── courses/       # 字母 + 语种 loader/validator（目标 Turkish）
├── data/          # drift CourseDatabase + Seeder + Repository 实现
├── di/            # GetIt + Injectable（renderer_module / audio_module）
├── domain/        # 领域模型 + Repository 接口
│   ├── course/    # section/unit/lesson/stage/interaction/sub_lesson/
│   │              # listening_phase/reading_passage/expression/grammar_point/
│   │              # lesson_word_link/srs_word/mistake_entry/word_entry
│   ├── audio/     # VocabAudioResolver 抽象
│   └── repositories/  # ICourseRepository, IStudyLogRepository
├── routing/       # Auto Route + CourseReadyGuard
├── service/       # AppPrefs / locator / TTS / 本地提醒
└── views/         # courses / dictionary / home / lesson / play / profile /
                   # review / ai / theme.dart
```

### 关键模式

- **状态管理**：Provider + ChangeNotifier
- **DI**：GetIt + Injectable
- **路由**：Auto Route + 代码生成 + `CourseReadyGuard`
- **模型**：Freezed 不可变 + JSON 序列化
- **Repository**：接口 + 实现；DB 作为派生缓存

---

## UI 主题

`VarnamalaTheme`（[lib/views/theme.dart](lib/views/theme.dart)）提供 `lightTheme` / `darkTheme` 及一组按 `Brightness` 自适应的语义化颜色 helper（`cardBg` / `scaffoldBg` / `textHintColor` / `inputFillColor` / `bottomNavBg` 等）。

```dart
// Primary: Teal/Cyan
const primaryColor = Color(0xFF1F727E);
const primaryLight = Color(0xFF359CBB);
const primaryDark  = Color(0xFF145A64);
// Accent
const secondary      = Color(0xFF46D1BF);
const secondaryLight = Color(0xFF00FFC6);
// Semantic
const error   = Color(0xFFE74C3C);
const success = Color(0xFFFFD93D);
const warning = Color(0xFFFF9F43);
```

`ThemeProvider`（`light / dark / system`）持久化到 `StreamingSharedPreferences`，Profile 页可切换。

---

## 课程数据格式

JSON 位于 `assets/courses/turkish/`，由 `CourseLoader` 加载、`DatabaseSeeder` seed 到 SQLite。最小 `index.json`：

```json
{
  "version": 7,
  "language": "tr",
  "displayName": "Turkish",
  "sections": [
    { "id": "section1", "name": "Section 1", "level": "A1",
      "prerequisiteSectionIds": [], "file": "sections/section1.json" }
  ]
}
```

每个 section 含 `units → lessons → content`（stages / subLessons / listeningPhases / readingPassage）。Interaction 变体由 `runtimeType` 区分。完整 authoring 契约见 [`docs/authoring/course-layout.md`](./docs/authoring/course-layout.md)。

---

## 构建与运行

```bash
flutter pub get        # 安装依赖（生成代码已提交，无需 build_runner）
flutter run            # 运行
```

首次启动从 bundle JSON seed `course.db`；之后复用缓存。强制 reseed：bump `index.json` 的 `version` 或清空 app data。

只有修改了 `@freezed` / `@JsonSerializable` / `@AutoRoute` / `@injectable` 注解后才需要重新生成：

```bash
flutter pub run build_runner build --delete-conflicting-outputs   # 或 make gen
```

### Makefile

```bash
make gen                # 生成代码
make test               # Dart 测试
make test-python        # Python 工具测试
make analyze            # 静态分析
make ci                 # analyze + test + test-python + build-release-smoke
make build-release VERSION=0.4.0-future4
```

环境要求：Flutter SDK `>=3.2.3 <4.0.0`。

---

## 测试

```bash
flutter test                                  # 385/385 通过
python3 -m unittest discover -s test -p "*_test.py"   # Python 工具 14 项
```

`flutter analyze` 仅 info 级 lint。`tool/course_cli.py validate` 对 8-section Turkish 课程通过。详情见 [`test/BASELINE.md`](./test/BASELINE.md)。

---

## 文档

| 文档 | 说明 |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | AI Agent 架构总览 |
| [`docs/decisions/`](./docs/decisions/) | ADR 0001–0020 |
| [`docs/content_inventory_current.md`](./docs/content_inventory_current.md) | Turkish 内容清单 |
| [`docs/authoring/course-layout.md`](./docs/authoring/course-layout.md) | authoring 契约 |
| [`docs/authoring/lesson-type-templates.md`](./docs/authoring/lesson-type-templates.md) | Lesson Template JSON 模板 |
| [`docs/authoring/gui-course-editor.md`](./docs/authoring/gui-course-editor.md) | GUI 编辑器设计契约 |
| [`docs/authoring/gui-beginner-guide.md`](./docs/authoring/gui-beginner-guide.md) | GUI 编辑器入门指南 |
| [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md) | 人工录音提交规范 |
| [`test/BASELINE.md`](./test/BASELINE.md) | 测试基线 |

---

## GUI 课程编辑器（作者工具）

位于 [`tool/gui/`](./tool/gui/)，基于 **PySide6**，复用 `tool/course_cli.py` 校验/归一化逻辑。JSON 仍是唯一真理源。

> 设计契约见 [`docs/authoring/gui-course-editor.md`](./docs/authoring/gui-course-editor.md)。

### 定位

- 打开 `assets/courses/<lang>/` 目录，三栏树（Section → Unit → Lesson）+ 右侧 detail 面板编辑所有 JSON 文件。
- detail 面板按 lesson 的 `template` 字段切换可用字段，非法结构在 UI 层不可构造。

### 两种编辑视图

1. **教师视图**：线性三层次（课 → 环节 → 步骤 → 题目），含 `LessonWizard`、`QuestionCards`、`TemplateEditors`、`VocabTable`、`ErrorMapper`。
2. **传统视图**：`CourseTree` + `LessonEditor` + `ResourceEditor` + `DetailPanel`。

### 教材导入（Textbook Import）

从外部教材（PDF/Word/图片/文本）提取语言教学内容，经多阶段向导流程导入课程树。核心模块：

**项目持久化**（`textbook_project.py`）——导入任务以项目为单位保存到 `tool/var/textbooks/`，含源文件引用、提取进度、用户决策，支持中断恢复与跨会话续传。

**多阶段导入向导**（`textbook_import_dialog.py`）——结构化分步流程：

1. **选材**：拖入 PDF/Word/图片/文本，自动识别文件类型并抽取可读文本（PDF 经 PyPDF2、Word 经 python-docx、图片经 base64 入 vision API）。
2. **提取**：调 AI 逐章识别词汇、表达、语法点、对话、练习，`KnowledgeExtractor` 按 `KnowledgeSchema` 产出结构化条目。
3. **合并**：`KnowledgeMerger` 跨章节去重合并，处理同一词汇的多次出现、释义冲突、例句归并。
4. **预览**：`BulkImportPreviewPanel` 展示全部拟导入条目，支持逐条确认、编辑、排除，按资源类型（词汇/表达/语法点）分 tab。
5. **导入**：确认后的条目写入 `vocab.json` / `expressions.json` / `grammar_points.json`，并生成对应 lesson。

**提取质量控制**（`extraction_quality.py`）——校验 AI 提取结果的完整性：必填字段检查、id 格式校验、题型引用有效性、语言方向一致性。

**导入策略**（`import_strategy.py`）——三种预设策略控制导入行为：

| 策略 | 新建 | 冲突 | 缺失 |
|---|---|---|---|
| 保守 | 跳过 | 跳过 | 跳过 |
| 激进 | 新建 | 覆盖 | 补充 |
| 交互式 | 确认 | 确认 | 确认 |

**并发与性能**——多文件提取阶段并发调 AI（可配并发数），大文件自动分段（`markdown_chopper.py`），支持断点续传。

**预设模板**（`textbook_presets.py`）——内置常用教材的语言对、CEFR 等级、题型偏好预设，一键填充向导参数。

### 工作区窗口（Workshop）

独立于课程树的 **Workshop 窗口**（`workshop_window.py`），与 App Shell（`app.py`）松耦合，共享项目上下文。集中管理批量操作：教材导入任务列表、AI 批量生成队列、跨 section 内容迁移、操作日志查看。支持多任务并行，后台执行不阻塞主编辑器。

### AI 生成引擎

AI 能力集中在下述后端模块，GUI 对话框仅做表单/聊天前端：

| 模块 | 职责 |
|---|---|
| `ai_generator.py` | 普通模式 + 许愿模式生成调度 |
| `ai_stream.py` | SSE 流式响应处理，实时显示生成进度 |
| `ai_fixer.py` | 生成后自动修复：id 冲突、引用断裂、schema 不符 |
| `ai_prompt_library.py` | 可复用的 prompt 模板库，按 template/CEFR/题型索引 |
| `ai_genre.py` | Genre 标签映射，多模板批量生成编排 |
| `ai_presets.py` | 常用模型/参数预设 |
| `ai_usage.py` | Token 用量追踪，按会话/项目统计 |

### AI 课程生成器

内置 AI 生成对话框，支持任意 OpenAI-compatible endpoint（API 配置仅存内存）。

- **普通模式**：表单填写语言/等级/单元数/主题 → AI 生成 section JSON → 可编辑预览 → 导入。
- **许愿模式**：多轮对话对齐需求 + 附件（图片/PDF/Word/文本）→ 点「我感觉差不多了」→ AI 生成 JSON + 解释。
- **Genre 批量生成**：在主题中插入 `[intro]`/`[practice]`/`[listening]`/`[reading]`/`[review]`/`[mastery]` 标签，一次生成多种模板的课。
- **流式输出**：SSE 实时显示生成进度，支持中途取消。
- **自动修复**：`ai_fixer.py` 生成后自动修复 id 冲突、引用断裂、schema 不符。

#### 护栏

| 护栏 | 实现 |
|---|---|
| **id 全局唯一** | id 只读；rename 只改 name；validate 兜底查重；导入冲突弹窗 |
| **scale ceiling** | 复用 `course_cli.py` 的 `MAX_UNITS_PER_SECTION=60` / `MAX_LESSONS_PER_UNIT=40` |
| **引用完整性** | `wordId`/`expressionId`/`grammarPointId` 从已加载资源下拉选 |
| **保存前校验** | `validate --format json` 失败 → 禁用保存 + 高亮问题节点 |
| **密钥不落盘** | API key/base URL/model 仅存内存；附件用临时文件 |

### 运行与打包

```bash
pip install PySide6
python tool/gui/src/main.py

# 打包
pip install pyinstaller
python tool/gui/build_gui.py              # onefile → dist/varnamala-gui.exe
python tool/gui/build_gui.py --onedir     # onedir
```

### 测试

```bash
python -m pytest tool/gui/tests/                 # GUI 单元测试
python -m pytest test/tool/gui_round_trip_test.py  # GUI ↔ CLI round-trip
```

---

## 听力音频生成（作者工具）

`listening` template 的 `listeningPhases[].audioAsset` 指向预生成 MP3。本项目用两步流水线离线生成，不在运行时调云端 TTS。

### 两步流水线

```
1. generate_audio.py    扫描 listeningPhases → 调 MiniMax TTS → 生成主内容 MP3
2. mix_listening_a1.py  主内容 + debut(开场) + fin(结尾) + bgm(BGM) → 混音成品
```

### 第一步：TTS 合成

[`tool/generate_audio.py`](./tool/generate_audio.py) 调 **MiniMax T2A v2 REST API** 批量合成。

```bash
export MINIMAX_API_KEY="sk-..."
export MINIMAX_GROUP_ID="..."        # 部分账号需要

python tool/generate_audio.py all                        # 全部 listening 资产
python tool/generate_audio.py all --voice-id male-qn-jingying --speed 0.9
python tool/generate_audio.py speak "Merhaba, nasılsın?" out.mp3
python tool/generate_audio.py all --force                 # 强制重生成
```

### 第二步：混音

[`tool/mix_listening_a1.py`](./tool/mix_listening_a1.py) 用 **pydub** 混音（需 ffmpeg）。

```bash
pip install pydub

python tool/mix_listening_a1.py all \
    --main-dir  assets/sounds/turkish/listening/raw_a1 \
    --debut-dir assets/sounds/turkish/listening/debut \
    --fin-dir   assets/sounds/turkish/listening/fin \
    --bgm-dir   assets/sounds/turkish/listening/bgm \
    --mapping   tool/mappings/a1_show_mapping.csv \
    --output-dir assets/sounds/turkish/listening/mixed_a1
```

混音结构：`debut + [主内容 + BGM(降 18dB)] + fin`，结尾 BGM 淡出 800ms。每节课映射到 A/B/C variant（不同 debut/fin/bgm 组合），CSV mapping 指定；未映射默认 A。

### 人工录音替换

人工录音可替换 TTS 文件，规范见 [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md)。文件名与 `audioAsset` 一致，放入 `assets/sounds/turkish/listening/`。

### 资产清单校验

```bash
python tool/course_cli.py audio-manifest --output manifest.csv
```

---

## 下一轮计划

- **内容创作**：以真实 Turkish 词汇、表达、语法点、听力阶段、阅读篇章充实 Sections 2–8。内容创作遵循以下语言学优先级：
  1. **高频词汇优先**：以 Turkish National Corpus 词频数据为指导，优先覆盖前 2000 词族（覆盖日常文本约 85%）。
  2. **语法渐进**：A1 集中于现在时、格标记（主格/宾格/与格/属格/方位格/离格）、简单句；A2 引入过去时与将来时；B1 引入关系从句与名物化结构；B2 涉及语篇衔接手段与语体变化。
  3. **语用真实性**：表达与对话应反映目标语的真实使用场景（如土耳其语中 `Buyurun` 的多重语用功能），避免翻译腔。
- 持续完善可访问性与统计指标。

---

## 致谢

- 原始框架：[Varnamala](https://github.com/rshrc/Varnamala) — Section/Unit/Lesson 树 + Provider + Drift + Freezed + auto_route 骨架。
- TTS：[flutter_tts](https://pub.dev/packages/flutter_tts)
- 持久化：[drift](https://pub.dev/packages/drift) + [streaming_shared_preferences](https://pub.dev/packages/streaming_shared_preferences)
- DI / 路由：[get_it](https://pub.dev/packages/get_it) + [injectable](https://pub.dev/packages/injectable) + [auto_route](https://pub.dev/packages/auto_route)

---

## License

见 [LICENSE](./LICENSE)。