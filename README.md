# Varnamala Plus

> 本地优先、离线的 Flutter 语言学习框架。当前目标语：**Turkish（土耳其语）**。

[![Flutter CI](https://github.com/rshrc/Varnamala/actions/workflows/flutter_ci.yml/badge.svg)](.github/workflows/flutter_ci.yml)

---

## 这是什么

基于上游 [Varnamala](https://github.com/rshrc/Varnamala) 的 Section/Unit/Lesson/SRS/错题本骨架，聚焦 **Turkish**，持续做减法。

- **纯本地**：SQLite（drift），无云后端/推送/登录。
- **单人离线**：无好友、排行榜、联赛、心数、宝石。
- **AI 协作开发**：工程决策记录在 `docs/decisions/`。

> 本仓库非上游官方版本；纯原版功能请访问 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)。

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

课程为 Turkish（ADR 0020）。8 个 CEFR 分级 Section（A1→B2，inter-section 前置依赖），Section 1 有真实内容，Sections 2–8 含 AI 生成的占位课程。

清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

---

## 框架已完成的能力

### 课程引擎

- **层级模型**：`Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction`（freezed + JSON 序列化）。
- **13 种 Interaction 题型**（`@injectable` 插件注册到 GetIt）：`showWord` / `multipleChoice` / `multiSelect` / `fillBlank` / `translateSentence` / `listenAndPick` / `typeTheWord` / `listenOnly` / `reorderSentence` / `readingMcq` / `readingTrueFalse` / `readingShortAnswer`。
- **6 种 Lesson Template**：`intro` / `practice` / `listening` / `reading` / `review` / `mastery`（+ `legacy` 兜底）。`Lesson.flattenedStages` 展平为渲染器可遍历的 `List<Stage>`。
- **按需加载**：`index.json` + per-section JSON + drift SQLite 缓存（schemaVersion 5，含 expressions 表），按内容版本号自动 reseed。

### 复习与练习

- **SRS**：SM-2 算法的单词 + 语法点队列；闪卡显示 "Learned in: <lesson>"。
- **错题本**：30 条 FIFO，含原始 interaction 快照，支持重做清除 + 跳转语法复习。
- **语法复习**：Explain → Practice → Rate 三段流，复用 Interaction 渲染器。
- **每日挑战**：从课程树随机抽取真实题项合成挑战课。
- **弱词复习**：近 30 天 ≥2 错次构建 10 题迷你 quiz。
- **Match Madness**：单词配对小游戏。
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
- 预录 `audioAsset` 预留给听力练习。

### 提醒

- **本地每日提醒**：`flutter_local_notifications` + 时间选择器，**无** streak repair。

### 工具与发布

- **发布流水线**：`tool/build_release.py` 一键生成版本化 APK/AAB/web 产物 + 内容清单。
- **内容 CLI**：`tool/course_cli.py`（校验 / lint / CSV 导入导出 / 音频清单 / diff）、`tool/export_content_inventory.py`、`tool/split_course.py`。
- **app 内置 AI 生成器**：实验性页面 `AiCourseGeneratorPage`，配置任意 OpenAI-compatible endpoint 生成 section JSON（配置仅存内存）。

> **GUI 课程编辑器**与**听力音频生成**是两个独立的作者工具链，详见下方专节。

---

## 已明确不做

- ❌ League/天梯/好友/排行榜/分享。
- ❌ Hearts/Streak Repair/商店道具。
- ❌ Speaking 录音匹配。
- ❌ 云端 CMS/Firebase/推送通知。
- ❌ GUI 替代 JSON 作为真理源。

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

从外部教材（PDF/Word/图片/文本）提取语言教学内容，多阶段流程导入课程树：

- **提取**：拖入教材文件，AI 识别词汇、表达、语法点、对话、练习。
- **知识合并**：`KnowledgeMerger` 去重合并提取结果，解决跨章节重复与冲突。
- **批量预览**：导入前预览全部拟导入条目，支持逐条确认/编辑/排除。
- **预设与策略**：内置多种导入策略（保守/激进/交互式），支持并发提取。

### 工作区窗口（Workshop）

独立于课程树的 **Workshop 窗口**，用于批量操作：教材导入、AI 批量生成、内容迁移等。与主编辑器共享同一项目上下文。

### AI 课程生成器（Beta）

内置 AI 生成对话框（[`tool/gui/src/dialogs/ai_generator_dialog.py`](./tool/gui/src/dialogs/ai_generator_dialog.py)），支持任意 OpenAI-compatible endpoint。API 配置仅存内存，关闭即丢。

#### 普通模式

表单式生成：填写目标语言/源语言/CEFR 等级/单元数/课时/课程类型/主题 → AI 返回 section JSON → 可编辑文本框检查修改 → 导入（id 冲突检测）。

#### 许愿模式（Wish Mode）

两阶段对话式生成：
1. **对齐**：多轮对话描述需求 + 拖入附件（图片/PDF/Word/文本），AI 用口语化中文回应，不输出 JSON。
2. **生成**：点「我感觉差不多了」→ AI 生成 section JSON + 通俗解释 → 导入课程树。

支持生成后继续对话修改，再次生成保留 draft 上下文。

#### Genre 多模板批量生成

在主题/额外指令中插入 genre 标签，在一个 section 内按标签生成不同模板的课：

| 标签 | template | 主键 | 建议题型 |
|---|---|---|---|
| `[intro]` | intro | subLessons | showWord / translateSentence / fillBlank |
| `[practice]` | practice | subLessons | multipleChoice / translateSentence / fillBlank / reorderSentence |
| `[review]` | review | subLessons | multipleChoice / fillBlank / translateSentence |
| `[listening]` | listening | listeningPhases | listenAndPick / typeTheWord / listenOnly |
| `[reading]` | reading | readingPassage | readingMcq / readingTrueFalse / readingShortAnswer |
| `[mastery]` | mastery | stages | multipleChoice / translateSentence / fillBlank / multiSelect |
| `[mixed]` | mixed | — | 混合 |

#### 护栏

| 护栏 | 实现 |
|---|---|
| **id 全局唯一** | id 只读；rename 只改 name；validate 兜底查重；导入冲突弹窗 |
| **scale ceiling** | 复用 `course_cli.py` 的 `MAX_UNITS_PER_SECTION=60` / `MAX_LESSONS_PER_UNIT=40` |
| **引用完整性** | `wordId`/`expressionId`/`grammarPointId` 从已加载资源下拉选 |
| **tags 白名单** | 多选下拉，选项 = `course_cli.py::ALLOWED_TAGS` |
| **template↔content 一致** | UI 按 template 切换字段 |
| **保存前校验** | `validate --format json` 失败 → 禁用保存 + 高亮问题节点 |
| **版本号 bump** | 「标记为内容发布」自动 bump 对应 version |
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

- **内容创作**：用真实 Turkish 词汇、表达、语法点、听力阶段、阅读篇章充实 Sections 2–8。
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