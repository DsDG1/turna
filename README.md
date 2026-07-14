# Varnamala Plus

> 本地优先、离线、零社交摩擦的 Flutter 语言学习框架。当前唯一目标语：**Turkish（土耳其语）**。

[![Flutter CI](https://github.com/rshrc/Varnamala/actions/workflows/flutter_ci.yml/badge.svg)](.github/workflows/flutter_ci.yml)

---

## 这是什么

**Varnamala Plus** 基于 Flutter，借用上游 [Varnamala](https://github.com/rshrc/Varnamala) 的 Section / Unit / Lesson / SRS / 错题本骨架，聚焦**单一目标语 Turkish**，持续做"减法"——去社交化、去 Duolingo 风格 friction。

- **纯本地**：SQLite 缓存（drift），无云后端 / 推送 / 登录。
- **单人离线**：无好友、无排行榜、无联赛、无心数、无宝石购买。
- **AI 协作开发（vibecoding）**：工程决策以 ADR 形式记录在 `docs/decisions/`。

> 本仓库非上游官方版本；如需纯原版功能请访问 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)。

## 快速开始

```bash
git clone <仓库地址>
cd VarnamalaPlus
flutter pub get
flutter run
```

> **生成代码已提交到版本库**（`.freezed.dart` / `.g.dart` / `.gr.dart` / `.gen.dart` / `injection.config.dart`），因此**新克隆无需先跑 `build_runner`**。只有当你修改了带 `@freezed`、`@JsonSerializable`、`@AutoRoute`、`@injectable` 注解的类时，才需要重新生成：
>
> ```bash
> flutter pub run build_runner build --delete-conflicting-outputs
> ```

### 当前内容状态

课程已迁移到 Turkish（ADR 0020）。8 个 CEFR 分级 Section（A1→B2，含 inter-section 前置依赖）就位，仅 Section 1 有真实内容：

| Section | Level | 状态 |
|---|---|---|
| Section 1 | A1 | ✅ 真实内容（8 词 + 2 表达，3 subLessons） |
| Sections 2–8 | A1→B2 | ⬜ 占位，等待内容填充 |

清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

---

## 框架已完成的能力

### 课程引擎

- **层级模型**：`Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction`（freezed + JSON 序列化）。
- **13 种 Interaction 题型**（`@injectable` 插件注册到 GetIt）：`showWord` / `multipleChoice` / `multiSelect` / `fillBlank` / `translateSentence` / `listenAndPick` / `typeTheWord` / `listenOnly` / `reorderSentence` / `readingMcq` / `readingTrueFalse` / `readingShortAnswer`。
- **6 种 Lesson Template**：`intro` / `practice` / `listening` / `reading` / `review` / `mastery`（+ `legacy` 兜底）。`Lesson.flattenedStages` 展平为渲染器可遍历的 `List<Stage>`。
- **按需加载**：`index.json` + per-section JSON + drift SQLite 缓存（schemaVersion 5，含 expressions 表），按内容版本号自动 reseed。

### 复习与练习

- **SRS**：SM-2 算法的单词 SRS + 语法点 SRS 队列；闪卡显示 "Learned in: <lesson>"。
- **错题本**：30 条 FIFO，含原始 interaction 快照，支持重做清除 + 跨路由跳转语法复习。
- **语法复习**：Explain → Practice → Rate 三段流，复用 Interaction 渲染器。
- **每日挑战**：从课程树随机抽取真实题项合成挑战课，复用 `LessonViewModel`。
- **弱词复习**：近 30 天 ≥2 错次构建 10 题迷你 quiz。
- **Match Madness**：单词配对小游戏。

### 检索与统计

- **词典 / 搜索**：搜单词、表达、语法点；`VocabAudioResolver` 播放音频。
- **学习统计仪表盘**：90 天 `StudyLog` 滚动 + 7 日 XP 趋势 + 时长 / 准确率 / 课数 / 弱词分析（Profile 页）。
- **课程树加载状态**：显式 `SectionLoadState` + 错误重试 UI。
- **内容更新提示**：检测课程版本变化，提示重置进度。

### 主题与可访问性

- **暗色 / 亮色 / 跟随系统**：`VarnamalaTheme` 语义化颜色 + `ThemeProvider` 持久化。
- **可访问性**：tooltip、MCQ 屏幕阅读语义、对比度感知配色。

### 音频 / TTS

- `AudioController` 统一接管 TTS，按 `TargetLanguage.ttsLanguageCode` 切语言。
- 运行时仅用系统 / Google TTS（`tr`）；Piper 离线模型与 `sherpa_onnx` 已移除（ADR 0020）。
- 预录 `audioAsset` 预留给听力练习（生成流水线见下方专节）。

### 提醒

- **本地每日提醒**：`flutter_local_notifications` + 时间选择器，**无** streak repair。

### 工具与发布

- **发布流水线**：`tool/build_release.py` 一键生成版本化 APK/AAB/web 产物 + 内容清单。
- **内容 CLI**：`tool/course_cli.py`（校验 / lint / CSV 导入导出 / 音频清单 / diff）、`tool/export_content_inventory.py`、`tool/split_course.py`。
- **app 内置 AI 生成器**：实验性页面 `AiCourseGeneratorPage`，配置任意 OpenAI-compatible endpoint 生成 section JSON（配置仅存内存）。

> **GUI 课程编辑器**与**听力音频生成**是两个独立的作者工具链，详见下方专节。

---

## 已明确**不**做的事（防 scope creep）

- ❌ League / 天梯 / 好友 / 排行榜 / 分享奖励 / Patreon。
- ❌ Hearts / Streak Repair / 商店道具。
- ❌ Speaking 录音匹配题型。
- ❌ 云端 CMS / Firebase / 推送通知。
- ❌ 把 GUI 当作内容真理源——GUI 只编辑 JSON 文件，JSON 仍是唯一真理源。

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
- **路由**：Auto Route + 代码生成 + `CourseReadyGuard`（DB 未 seed 时重定向到 splash）
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
| [`CLAUDE.md`](./CLAUDE.md) | AI Agent 架构总览与 onboarding |
| [`docs/decisions/`](./docs/decisions/) | ADR 0001–0020 |
| [`docs/decisions/0003-audio-generation-strategy.md`](./docs/decisions/0003-audio-generation-strategy.md) | 音频生成策略 |
| [`docs/decisions/0020-swahili-to-turkish-pivot.md`](./docs/decisions/0020-swahili-to-turkish-pivot.md) | Swahili→Turkish 迁移 |
| [`docs/content_inventory_current.md`](./docs/content_inventory_current.md) | Turkish 内容清单 |
| [`docs/authoring/course-layout.md`](./docs/authoring/course-layout.md) | authoring 契约 |
| [`docs/authoring/lesson-type-templates.md`](./docs/authoring/lesson-type-templates.md) | Lesson Template JSON 模板 |
| [`docs/authoring/gui-course-editor.md`](./docs/authoring/gui-course-editor.md) | GUI 编辑器设计契约 |
| [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md) | 人工录音提交规范 |
| [`test/BASELINE.md`](./test/BASELINE.md) | 测试基线 |

---

## GUI 课程编辑器（作者工具）

Varnamala Plus 附带一个**本地桌面 GUI 课程编辑器**，位于 [`tool/gui/`](./tool/gui/)，基于 **PySide6** 构建。它是一个**受约束的表单前端**，后端复用 `tool/course_cli.py` 的校验/归一化逻辑——**JSON 仍是唯一真理源**，GUI 不另立标准。

> 设计契约见 [`docs/authoring/gui-course-editor.md`](./docs/authoring/gui-course-editor.md)。`CLAUDE.md` 把 "External GUI editor" 列为 Removed 指的是「把 GUI 当内容真理源」的方向；本 GUI 只编辑 JSON 文件，与人工编辑等价。

### 定位

- 打开 `assets/courses/<lang>/` 目录，以三栏树（Section → Unit → Lesson）+ 右侧 detail 面板编辑 `index.json`、`sections/*.json`、`vocab.json`、`expressions.json`、`grammar_points.json`。
- 所有读写落到这些 JSON 文件，**不**写 app 的 SQLite 缓存。
- detail 面板按 lesson 的 `template` 字段切换可用字段，让非法结构在 UI 层就构造不出来。

### 两种编辑视图

1. **教师视图（Teacher / Linear Flow）**：线性三层次（课 → 环节 → 步骤 → 题目）编辑，位于 [`tool/gui/src/teacher/`](./tool/gui/src/teacher/)。含 `LessonWizard`、`QuestionCards`、`TemplateEditors`、`VocabTable`、`ErrorMapper`。
2. **传统视图（Classic）**：`CourseTree` + `LessonEditor` + `ResourceEditor` + `DetailPanel`，位于 [`tool/gui/src/widgets/`](./tool/gui/src/widgets/)。

### AI 课程生成器（GUI 内置，Beta）

GUI 内置一个功能完整的 **AI 课程生成对话框**（[`tool/gui/src/dialogs/ai_generator_dialog.py`](./tool/gui/src/dialogs/ai_generator_dialog.py) + 后端 [`tool/gui/src/backend/ai_generator.py`](./tool/gui/src/backend/ai_generator.py)），支持任意 OpenAI-compatible endpoint（OpenAI / DeepSeek / Moonshot / 本地 Ollama 等）。**API 配置仅存内存，关闭程序即丢失，绝不写盘。**

#### 普通模式（Normal）

表单式直接生成：
- 填写 **目标语言**（默认 Turkish）/ **源语言**（默认 Chinese，用于 prompt 和 hints）/ **CEFR 等级**（A1–C1）/ **单元数**（1–5）/ **每单元课时**（1–5）/ **课程类型** / **主题** / **额外指令**。
- 选择**课程类型**：混合 / 认识新词(intro) / 巩固练习(practice) / 复习(review) / 听力训练(listening) / 阅读理解(reading) / 综合测验(mastery)。
- 点击「生成课程」→ AI 返回 section JSON，显示在**可编辑 JSON 文本框**中供检查与修改。
- 支持「恢复 AI 原始输出」（撤销手动编辑）和「校验 JSON」（解析 + 检查 `units` 数组）。
- 导入前做 id 冲突检测，若 section id 已存在则弹窗要求改名。

#### 许愿模式（Wish Mode）

对话式对齐 + 附件 + 最终生成，两阶段流程：

```
阶段 1 对齐（Alignment）        阶段 2 生成（Generation）
用户描述需求 + 拖入附件    →    AI 用大白话解释设计    →    用户点"我感觉差不多了"    →    AI 返回 section JSON + 通俗解释
（多轮，AI 不输出 JSON）                                                        （导入到课程树）
```

- **多轮对话**：像聊天一样描述课程需求，AI 用**口语化中文**回应（不含 jargon / JSON / markdown），每轮先总结理解再给 2-3 条具体建议或澄清问题。`Ctrl+Enter` 发送。
- **文件附件**（拖拽到窗口）：支持图片（png/jpg/jpeg/gif/webp，转 base64 `image_url`）、PDF（PyPDF2 抽文本）、Word（doc/docx，python-docx 抽文本）、纯文本（txt/md/csv/json/py/dart/yaml 等）。附件复制到临时文件，对话框关闭时自动删除。
- **「我感觉差不多了」按钮**：触发最终生成，AI 根据整段对话 + 规格生成 section JSON，随后再调一次 AI 用通俗语言解释生成的课程。
- 支持**继续对话修改**——生成后仍可继续聊天要求调整，再次点按钮重新生成（保留 draft JSON 上下文）。

#### Genre 多模板批量生成（Beta）

开启「启用 [genre] 多模板批量生成」开关后，可在**主题**或**额外指令**中插入 genre 标签，让 AI 在一个 section 内按标签生成不同模板的课：

| 标签 | template | 主键 | 建议题型 |
|---|---|---|---|
| `[intro]` | intro | subLessons | showWord / translateSentence / fillBlank |
| `[practice]` | practice | subLessons | multipleChoice / translateSentence / fillBlank / reorderSentence |
| `[review]` | review | subLessons | multipleChoice / fillBlank / translateSentence |
| `[listening]` | listening | listeningPhases | listenAndPick / typeTheWord / listenOnly |
| `[reading]` | reading | readingPassage | readingMcq / readingTrueFalse / readingShortAnswer |
| `[mastery]` | mastery | stages | multipleChoice / translateSentence / fillBlank / multiSelect |
| `[mixed]` | mixed | — | 混合 |

例如主题填「旅行词汇 [intro] [listening]」会生成 intro + listening 两种模板的课。带标签的课用对应模板，无标签的回退到默认模板。UI 会实时检测标签并自动切换「课程类型」下拉框。映射逻辑在 [`tool/gui/src/backend/ai_genre.py`](./tool/gui/src/backend/ai_genre.py)。

#### Prompt 构建

后端 `build_prompt` / `build_alignment_prompt` 按 `spec.template` 生成对应的 JSON schema 示例（listening 用 `listeningPhases`，reading 用 `readingPassage + stages`，mastery 用单 `stages`，其余用 `subLessons`），并注入完整题型说明、id 规则（`ai-` 前缀 kebab-case、全局唯一）与 source/target 语言方向约束。

#### 护栏

| 护栏 | 实现方式 |
|---|---|
| **id 全局唯一 & 不可变** | id 字段只读；rename 只改 `name`；保存前 `validate` 兜底查重；导入时 id 冲突弹窗改名 |
| **scale ceiling** | 复用 `course_cli.py` 的 `MAX_UNITS_PER_SECTION=60` / `MAX_LESSONS_PER_UNIT=40`，达上限禁用新增 |
| **引用完整性** | `wordId` / `expressionId` / `grammarPointId` 用下拉框从已加载资源选，杜绝悬空引用 |
| **tags 白名单** | 多选下拉，选项 = `course_cli.py::ALLOWED_TAGS`（15 个） |
| **template↔content 一致** | UI 层按 template 切换字段，非法组合不可构造 |
| **保存前校验** | `validate --format json` 失败 → 禁用保存按钮 + 高亮问题节点 |
| **版本号 bump** | 「标记为内容发布」按钮自动检测改动文件并 bump 对应 `version` |
| **密钥不落盘** | API key / base URL / model 仅存内存；附件用临时文件，关闭即删 |

### 运行与打包

```bash
# 从源码运行（需 PySide6）
pip install PySide6
python tool/gui/src/main.py

# 打包为单文件 exe（需 PyInstaller）
pip install pyinstaller
python tool/gui/build_gui.py              # onefile → dist/varnamala-gui.exe
python tool/gui/build_gui.py --clean      # 先清 build/ dist/
python tool/gui/build_gui.py --onedir     # onedir 而非 onefile
```

### 测试

```bash
python -m pytest tool/gui/tests/                 # GUI 单元测试（107+ 项）
python -m pytest test/tool/gui_round_trip_test.py  # GUI ↔ CLI round-trip
```

---

## 听力音频生成（作者工具）

听力课程（`listening` template）的 `listeningPhases[].audioAsset` 指向预生成的 MP3。本项目用**两步流水线**离线生成，**不在运行时调云端 TTS**。

> 决策依据：ADR 0003（混合策略）。ADR 0003 原写于 Swahili 时代提及 Piper——Piper 与 `sherpa_onnx` 已在 ADR 0020 移除，运行时 TTS 走系统/Google `'tr'`；预生成听力音频改用 MiniMax TTS API。

### 两步流水线

```
1. generate_audio.py    扫描 listeningPhases → 调 MiniMax TTS → 生成主内容 MP3
2. mix_listening_a1.py  主内容 + debut(开场) + fin(结尾) + bgm(BGM) → 混音成品
```

### 第一步：TTS 合成主内容

[`tool/generate_audio.py`](./tool/generate_audio.py) 调 **MiniMax T2A v2 REST API** 批量合成。

```bash
export MINIMAX_API_KEY="sk-..."
export MINIMAX_GROUP_ID="..."        # 部分账号需要

python tool/generate_audio.py all                              # 全部 listening 资产
python tool/generate_audio.py all --voice-id male-qn-jingying --speed 0.9
python tool/generate_audio.py speak "Merhaba, nasılsın?" out.mp3  # 任意文本
python tool/generate_audio.py all --force                       # 强制重生成
```

**扫描规则**（`collect_entries`）：只处理 `listening` template 的 lesson，取 `listeningPhases[].audioAsset` + `transcript`（transcript 为合成文本）；跳过等于 `wordId`/`expressionId` 的项（单词/表达发音走运行时 TTS）；无 `transcript` 的 `audioAsset` 被跳过。

**输出**：`assets/sounds/turkish/listening/{assetId}.mp3`（默认 voice `female-tianmei`，model `speech-2.8-hd`，speed 0.9，32kHz / 128kbps / mono）。

### 第二步：混音

[`tool/mix_listening_a1.py`](./tool/mix_listening_a1.py) 用 **pydub** 混音（需 ffmpeg on PATH）。

```bash
pip install pydub

python tool/mix_listening_a1.py all \
    --main-dir  assets/sounds/turkish/listening/raw_a1 \
    --debut-dir assets/sounds/turkish/listening/debut \
    --fin-dir   assets/sounds/turkish/listening/fin \
    --bgm-dir   assets/sounds/turkish/listening/bgm \
    --mapping   tool/mappings/a1_show_mapping.csv \
    --output-dir assets/sounds/turkish/listening/mixed_a1

python tool/mix_listening_a1.py one main.mp3 --variant A   # 单个文件
```

**混音结构**：`debut + [主内容 + BGM(降 18dB)] + fin`，结尾 BGM 淡出 800ms。

**Show variant**：每节课映射到 A/B/C（对应不同 debut/fin/bgm 组合），CSV mapping 指定：

```csv
S1U1L01,A
S1U1L02,B
S1U1L03,C
```

未在 mapping 中的默认 A，输出 `S1U1L01A_mixed.mp3`。

### 人工录音替换

人工录音可替换 TTS 文件，规范见 [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md)：MP3 / 44.1kHz / mono 优先 / ≥128kbps / 首尾静音 ≤0.3s，文件名与 `audioAsset` 一致，放入 `assets/sounds/turkish/listening/`，提交前跑 `course_cli.py validate` + `audio-manifest`。

### 资产清单校验

```bash
python tool/course_cli.py audio-manifest --output manifest.csv   # 列出所有引用及文件存在状态
```

CI workflow `course_validation.yml` 验证课程仍通过校验。

---

## 下一轮计划

- **内容创作**：用真实 Turkish 词汇、表达、语法点、听力阶段、阅读篇章填充 Sections 2–8。Section 1 已作为样板完成（`s1-l2`：8 词 + 2 表达，3 subLessons）。
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