# Turna

> 本地优先、离线的 Flutter 语言学习框架。当前目标语：**Turkish（土耳其语）**。
> 复习引擎基于 **FSRS**，可导入 **Anki** 牌组，AI 能力由统一引擎层 + AI Hub 承载。

[![Flutter CI](https://github.com/rshrc/Varnamala/actions/workflows/flutter_ci.yml/badge.svg)](.github/workflows/flutter_ci.yml)

> 详尽的设计与实现说明见 [`docs/project-guide.md`](./docs/project-guide.md)。本 README 给出概览与快速上手。

---

## 这是什么

基于上游 [Turna](https://github.com/rshrc/Varnamala) 的 Section/Unit/Lesson/SRS/错题本骨架，聚焦 **Turkish**，持续深化：FSRS 复习引擎、Anki 牌组导入与高保真渲染、统一 AI 引擎层。

- **纯本地**：SQLite（drift，schemaVersion 14），无云后端/推送/登录。
- **单人离线**：无好友、排行榜、联赛、心数、宝石。
- **多平台**：Android、HarmonyOS（OHOS Flutter 分支）、iOS、Web（有限）。
- **教学法驱动**：功能取舍以二语习得研究为依据。

> 本仓库非上游官方版本；纯原版功能请访问 [rshrc/Turna](https://github.com/rshrc/Varnamala)。

---

## 教学法基础

本项目课程设计与复习机制建立在二语习得（SLA）与认知心理学研究之上（详尽论述见 `docs/project-guide.md` §2）：

- **可理解输入 / i+1**（Krashen）：CEFR 分级 Section（A1->B2）+ inter-section 前置依赖，工程化实现"略高于当前水平"的输入。
- **遗忘曲线 / 间隔重复**（Ebbinghaus）：在遗忘临界点附近安排复习。复习引擎采用 **FSRS**，以目标保持率（默认 0.9）驱动间隔计算，比传统 SM-2 更贴近真实遗忘曲线。
- **测试效应**（Roediger & Karpicke）：填空、翻译、听写、选择等题型本质是不同形式的主动检索，而非单纯考核。
- **技能习得理论**（DeKeyser）：语法复习采用 Explain -> Practice -> Rate 三段流，从陈述性知识向程序性技能转化。
- **交错练习**（Rohrer & Taylor）：每日挑战跨题型跨单元交错出题，长期保持优于集中练习。
- **错误分析**（Corder）：错题本保留原始快照，使错误成为可分析的中介语数据。

**关于土耳其语**：突厥语系黏着语，核心特征为元音和谐、SOV 语序、无语法性别、浅层正字法（拼读规则）。对汉语母语者既有门槛（语序、黏着形态）也有便利（无性别、拼读一致）。本项目据此设计渐进式语法复习与词形变化练习。

---

## 快速开始

```bash
git clone git@gitee.com:dhwdwf3/Varnamalaplus.git
cd Varnamalaplus
flutter pub get
flutter run
```

> **生成代码已提交**（`.freezed.dart` / `.g.dart` / `.gr.dart` / `injection.config.dart`），新克隆**无需** `build_runner`。仅当修改 `@freezed` / `@JsonSerializable` / `@AutoRoute` / `@injectable` 注解时才需重新生成：
>
> ```bash
> flutter pub run build_runner build --delete-conflicting-outputs   # 或 make gen
> ```

### 当前内容状态

课程为 Turkish。8 个 CEFR 分级 Section（A1->B2），含 inter-section 前置依赖；课程内容版本 10。Section 1（A1）有真实 intro 问候课（8 词 + 2 表达），Sections 2–8 为元数据占位。清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

---

## 框架能力

### 课程引擎

- **层级模型**：`Section -> Unit -> Lesson -> SubLesson / ListeningPhase / ReadingPassage -> Stage -> Interaction`（freezed + JSON）。
- **13 种 Interaction 题型**（`@injectable` 插件注册），按技能分类：词汇呈现（`showWord`）、接受性词汇（`multipleChoice` / `multiSelect`）、产出性句法（`fillBlank` / `translateSentence` / `reorderSentence` / `typeTheWord`）、听力（`listenAndPick` / `listenOnly`）、阅读（`readingMcq` / `readingTrueFalse` / `readingShortAnswer`）、Anki 保真（`ankiHtmlCard`）。
- **6 种 Lesson Template**：intro（认识新词）/ practice（巩固）/ listening（三段式听力）/ reading（篇章理解）/ review（交错复习）/ mastery（综合测验），另含 `legacy` 兜底。
- **按需加载**：`index.json` + per-section JSON + drift SQLite 缓存（schemaVersion 14，含 expressions 表），按内容版本号自动 reseed。

### 复习与练习

- **SRS（FSRS）**：基于 [fsrs](https://pub.dev/packages/fsrs) 包的间隔重复引擎（`lib/core/fsrs_engine.dart`），目标保持率 0.9、间隔上限 730 天、可 fuzz；失败走当日重学阶梯（`fsrs_relearn.dart`）；可选参数优化（`fsrs_optimizer.dart`）按个人复习历史拟合权重。SM-2 作为后备调度器保留。SRS 状态与复习历史持久化到 SQLite（`SrsStates` / `ReviewEvents` 表）。
- **记忆曲线**：`MemoryCurveProvider` 计算当前保持率（R=exp(-Δt/S)）、到期预测（今日/7 日/30 日）、成熟度（new/young/mature/leech）、按间隔分桶的经验回忆率曲线；Profile 页 `fl_chart` 可视化。
- **错题本**：30 条 FIFO，保留原始 interaction 快照，支持重做与跳转语法点复习。
- **语法复习**：Explain -> Practice -> Rate 三段流。
- **每日挑战**：随机抽题合成挑战课，交错练习。
- **弱词复习**：近 30 天错误 ≥2 次的词汇汇聚为 10 题迷你 quiz。
- **Match Madness**：限时单词配对小游戏，强化形式-意义连接自动化。
- **Anki 复习**：到期 Anki 卡片复习入口（见下节）。
- **AI 辅助**：提示助手、深度讲解、SRS 导师（见 AI 节）。

### Anki 集成

直接导入 `.apkg` 牌组作为课程树的一个 Section，与本应用 SRS / 错题 / 统计双向打通。设计见 [`docs/anki-deep-adaptation-plan.md`](./docs/anki-deep-adaptation-plan.md)。

- **导入流水线**：解析 notetypes/notes/cards/revlog -> 持久化 NoteStore（三表）-> 装配为 Section->Unit->Lesson -> 媒体拷贝 -> revlog 迁移为复习历史（FSRS 调度）。
- **智能组织**：从 notetype 字段名抽取 unit/lesson 键分组（deck 名兜底）。
- **Notetype 映射**：9 种结构化类型，导入预览可逐 notetype 编辑（front/back 字段）+ 「AI 智能识别」按钮。
- **Full / Lite 模式**：<2k 卡建完整课程树，≥2k 卡仅 shell Section（复习走保真路径）。
- **保真渲染**：复杂 notetype 由 `AnkiRenderPolicy` 逐卡判定，以 `ankiHtmlCard` + WebView 渲染原 HTML/CSS（仅 Android/iOS；HarmonyOS/Web/桌面文本兜底），支持暗色 CSS。
- **智能去解密**：含混淆解密 JS 的牌组首次复习时在 WebView 跑一次 JS 并缓存纯 HTML，后续复习无 JS/无网络。
- **浏览与统计**：卡片浏览器 + 牌组统计页。

### AI 能力

统一 AI 引擎层（`lib/application/ai/engine/`）是全应用唯一 LLM 出入口：双模型配置（chat / JSON）+ 严格 schema 模式 + 流式/取消 + SHA-256 缓存 + 预设（deepseek 默认 / openai / moonshot / ollama / custom）。配置持久化到本地（API key 写入绕过日志）。集中入口为 **AI Hub**（从 Play Hub 进入）：Hero 配置 / Continue 最近任务 / Start 五大功能 / Tools 测试连接与清缓存。

| 功能 | 说明 |
|---|---|
| **AI 提示助手** | 课程内聊天面板，按当前题目上下文给提示与解释。 |
| **深度讲解** | 4 种 genre：语法讲解 / 近义词辨析 / 句子拆解 / 错因分析。 |
| **SRS 导师** | 据错题 + 弱词 + 近期复习，AI 生成复习课写入课程树。 |
| **许愿生成** | 多轮对话对齐需求 + 附件 -> 滑动确认生成 section JSON + 通俗解释。 |
| **教材导入** | 从 PDF/Word/图片/文本提取词汇/表达/语法点，多阶段向导导入。 |
| **Lesson 助手** | 课程内 AI 辅助。 |
| **小艺 (Xiaoyi)** | HarmonyOS 系统 AI 助手桥接（`XiaoyiService` + 原生插件）；仅 OHOS 支持，其他平台自动回退 DeepSeek。 |

### 检索与统计

- **词典/搜索**：搜单词、表达、语法点；`VocabAudioResolver` 播放音频。
- **学习统计仪表盘**：90 天 `StudyLog` + 7 日 XP 趋势 + 时长/准确率/课数/弱词分析 + 记忆曲线。
- **课程管理页**：Settings 内集中查看/管理已导入课程。
- **进度导出/导入**：Settings 页支持学习进度 JSON 导出与恢复。
- **课程树加载状态**：显式 `SectionLoadState` + 错误重试 UI。
- **内容更新提示**：检测课程版本变化，提示重置进度。

### 主题与可访问性

- **主题**：亮 / 暗 / 跟随系统，`TurnaTheme` 语义化颜色 + 高对比主题变体 + Play Hub 毛玻璃。`ThemeProvider` 持久化。
- **可访问性**（`AccessibilityProvider`，6 项持久化偏好）：文本缩放 100–200%、减少动画、高对比、阅读障碍字体（Lexend）、感官减负（静音音效/触觉）、专注模式。

### 音频 / TTS

- `AudioController` 统一接管 TTS（`tr`）与音效；Piper 离线模型已移除。
- **智能朗读**（`language_detector.dart` + `smart_speech.dart`）：按脚本自动检测语言（Han->zh / Kana->ja / Cyrillic->ru / Turkish 特有字符->tr / 纯 Latin->母语回退），MCQ 选项与 Anki 正反面朗读按推断语言发声。
- **每课程设置**：自动朗读开关 + 母语语言选择。
- 预录 `audioAsset` 预留听力练习，支持三段式结构（debut + main + fin）+ BGM。

### 提醒

- **本地每日提醒**：`flutter_local_notifications` + 时间选择器，**无** streak repair。

### 应用外壳

- **离线 Changelog**：`ChangelogPage` 硬编码里程碑清单，Settings/About 进入，全离线可用。
- **品牌图标**：统一应用图标 + 启动 logo，`tool/generate_logo_variants.py` 生成多平台变体。

### 工具与发布

- **发布流水线**：`tool/build_release.py` 一键生成版本化 APK/AAB/可选 web + 内容清单。
- **内容 CLI**：`tool/course_cli.py`（校验/lint/CSV 导入导出/音频清单/diff）、`tool/export_content_inventory.py`、`tool/split_course.py`。
- **GUI 课程编辑器**：完整 PySide6 桌面编辑器（教材导入、AI 生成、Workshop、操作日志），详尽说明见 `docs/project-guide.md` §11。

### 课程编辑器 (tool/gui)

[`tool/gui/`](./tool/gui/) 是一个面向课程创作者 / 教师的 **PySide6 桌面编辑器**——把 `tool/course_cli.py` 的能力包成可视化界面。**不进 App 本体**，与上游"已移除外部 GUI 编辑器"立场一致；它是仓库内给内容创作者用的桌面工具。

**核心功能**：

- 🌳 **三级课程树直观编排**：Section → Unit → Lesson 层级化展示，支持拖拽排序、批量复制/移动、删除与预设套用。
- 🎨 **可视化蓝图与表单引擎**：针对 6 种课时模板（`intro` / `practice` / `listening` / `reading` / `review` / `mastery`）提供动态属性表单与编排蓝图。
- 🤖 **AI 课程工坊（统一创意画布）**：非模态三栏画布（教材 / 知识 / 气泡 · AI 轨道 · 大纲 / 设计 / 导入），支持教材提取、Grounded 生成、局部重生成与幂等导入。
- 📦 **语言资源独立建模**：词汇 (`vocab`)、固定表达 (`expressions`)、语法点 (`grammar_points`) 集中化表格管理，支持 CSV 导入导出与引用依赖检测。
- 🛡️ **单一校验源与保存回滚**：编辑器不另立校验规则，完全对接 `course_cli validate & lint`，保存失败自动恢复内存与磁盘。
- 🎓 **教师预览与试做模式**：可切换教师视角审查课程结构，并对编写中的课时进行实时交互试做。
- 🚀 **版本控制与发布工作流**：整合版本 Bump、音频 Manifest 挂载检查、Diff 差异比对与发布报告一键生成。

需要 Python 3.11+：

```bash
python -m tool.gui.src.main
```

完整功能、快捷键与打包说明见 [`tool/gui/README.md`](./tool/gui/README.md) 与 [`docs/authoring/gui-course-editor.md`](./docs/authoring/gui-course-editor.md)。

---

## 已明确不做

以下"游戏化"机制的移除是教学法决策（依据见 `docs/project-guide.md` §15）：

- ❌ League / 天梯 / 好友 / 排行榜 / 分享（社会比较抑制内在动机）
- ❌ Hearts / Streak Repair / 商店道具（惩罚机制导致回避高难度内容）
- ❌ Speaking 录音匹配（非主流语种语音评分效度不足）
- ❌ 云端 CMS / Firebase / 推送通知（本地优先保隐私与离线）
- ❌ GUI 替代 JSON 作为真理源（JSON 始终唯一权威，可版本化/diff/批处理）
- ❌ XP 倍率 / 宝石购买 / 社交成就

---

## 架构

Clean architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route。

```
lib/
├── application/   # Providers + 应用服务
│   ├── ai/        # AI 能力（engine/ 统一引擎层 + hint/wish/course/tutor）
│   ├── anki/      # Anki 导入/装配/渲染/复习/SRS 迁移
│   ├── srs_provider / grammar_review / srs_queue_provider（FSRS 调度）
│   ├── srs_tutor_provider / mistake / study_stats / memory_curve
│   ├── score / streak / progress / milestone / game(facade) / weak_word
│   ├── audio_controller / smart_speech / accessibility / settings …
├── core/          # fsrs_engine / sm2 / language_detector / html_stripper /
│                  # streak_resolver / logger
├── courses/       # 字母 + 语种 loader/validator（目标 Turkish）
├── data/          # drift CourseDatabase（schemaVersion 14）+ Seeder + DAO + Repository
├── di/            # GetIt + Injectable（renderer_module / audio_module）
├── domain/        # 领域模型 + Repository 接口（course / audio / repositories）
├── routing/       # Auto Route + CourseReadyGuard
├── service/       # AppPrefs / locator / TTS / 本地提醒
└── views/         # courses / dictionary / home / lesson / play / profile /
                   # review / ai / anki / settings / theme.dart
```

### 关键模式

- **状态管理**：Provider + ChangeNotifier
- **DI**：GetIt + Injectable
- **路由**：Auto Route + 代码生成 + `CourseReadyGuard`
- **模型**：Freezed 不可变 + JSON 序列化
- **Repository**：接口 + 实现；DB 作为派生缓存

---

## UI 主题

`TurnaTheme`（[lib/views/theme.dart](lib/views/theme.dart)）提供 `lightTheme` / `darkTheme` / 高对比变体，及一组按 `Brightness` 自适应的语义化颜色 helper（`cardBg` / `scaffoldBg` / `textHintColor` / `inputFillColor` / `bottomNavBg` 等）。

```dart
const primaryColor   = Color(0xFF1F727E);   // Teal/Cyan
const primaryLight   = Color(0xFF359CBB);
const secondary      = Color(0xFF46D1BF);
const secondaryLight = Color(0xFF00FFC6);
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
  "version": 10,
  "language": "tr",
  "displayName": "Turkish",
  "sections": [
    { "id": "section1", "name": "Section 1", "level": "A1",
      "prerequisiteSectionIds": [], "file": "sections/section1.json" }
  ]
}
```

每个 section 含 `units -> lessons -> content`（stages / subLessons / listeningPhases / readingPassage）。Interaction 变体由 `runtimeType` 区分。完整 authoring 契约见 [`docs/authoring/course-layout.md`](./docs/authoring/course-layout.md)。

---

## 构建与运行

```bash
flutter pub get        # 安装依赖（生成代码已提交，无需 build_runner）
flutter run            # 运行
```

首次启动从 bundle JSON seed `course.db`；之后复用缓存。强制 reseed：bump `index.json` 的 `version` 或清空 app data。

```bash
flutter pub run build_runner build --delete-conflicting-outputs   # 修改注解后生成（或 make gen）
```

### 平台

Android / iOS / HarmonyOS / Web（有限）。HarmonyOS 基于 **OpenHarmony Flutter 分支**（`3.35.8-ohos-1.0.4-beta`），需 JDK 17 + 源码补丁（`tool/apply_patches.sh`），配置见 [`docs/android-build-setup.md`](./docs/android-build-setup.md)。Anki 保真 WebView 仅 Android/iOS，其余平台文本兜底。

### Makefile

```bash
make gen                # 生成代码
make test               # Dart 测试
make test-python        # Python 工具测试
make analyze            # 静态分析
make ci                 # analyze + test + test-python + build-release-smoke
make build-release VERSION=0.4.0-future4
```

环境要求：Flutter SDK `>=3.2.3 <4.0.0`（OHOS 分支 3.35.8）。

---

## 测试

```bash
flutter test                                  # 800/0 绿（最新数字见 test/BASELINE.md）
python3 -m unittest discover -s test -p "*_test.py"            # Python 工具 14 项
python3 -m unittest discover -s tool/gui/tests -p "test_*.py"  # GUI 804 项
```

`flutter analyze`：改动文件 0 error / 0 warning（仅历史 info 级 lint）。`tool/course_cli.py validate` 对 Turkish 课程通过。详情见 [`test/BASELINE.md`](./test/BASELINE.md)。

---

## 文档

| 文档 | 说明 |
|---|---|
| [`docs/project-guide.md`](./docs/project-guide.md) | **详尽版**：架构、FSRS、Anki、AI 引擎、教学法、平台全解 |
| [`CLAUDE.md`](./CLAUDE.md) | AI Agent 架构总览 |
| [`docs/content_inventory_current.md`](./docs/content_inventory_current.md) | Turkish 内容清单 |
| [`docs/anki-deep-adaptation-plan.md`](./docs/anki-deep-adaptation-plan.md) | Anki 深度适配计划 |
| [`docs/anki-import-design.md`](./docs/anki-import-design.md) | Anki 导入设计 |
| [`docs/android-build-setup.md`](./docs/android-build-setup.md) | OHOS 分支构建配置 |
| [`docs/authoring/course-layout.md`](./docs/authoring/course-layout.md) | authoring 契约 |
| [`docs/authoring/lesson-type-templates.md`](./docs/authoring/lesson-type-templates.md) | Lesson Template JSON 模板 |
| [`docs/authoring/gui-course-editor.md`](./docs/authoring/gui-course-editor.md) | GUI 编辑器设计契约 |
| [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md) | 人工录音提交规范 |
| [`test/BASELINE.md`](./test/BASELINE.md) | 测试基线 |

---

## 听力音频生成（作者工具）

`listening` template 的 `listeningPhases[].audioAsset` 指向预生成 MP3，两步流水线离线生成（详尽见 `docs/project-guide.md` §12）：

1. `tool/generate_audio.py` 调 MiniMax T2A v2 批量合成主内容 MP3。
2. `tool/mix_listening_a1.py`（pydub，需 ffmpeg）混音 `debut + [主内容 + BGM(降 18dB)] + fin`，每节课映射 A/B/C variant。

人工录音可替换 TTS 文件，规范见 [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md)。

---

## 下一轮计划

- **内容创作**：以真实 Turkish 词汇、表达、语法点、听力阶段、阅读篇章充实 Sections 2–8。优先级：高频词汇（前 2000 词族）、语法渐进（A1 现在时/格标记 -> A2 过去/将来 -> B1 关系从句/名物化 -> B2 语篇衔接）、语用真实性。
- **Anki 二期**：review-ops（undo/suspend/bury/flag）、per-deck stats/browser/export、`{{type:}}` 输入桥、OHOS import sqlite3 FFI。
- 持续完善可访问性与统计指标。

---

## 致谢

- 原始框架：[Turna](https://github.com/rshrc/Varnamala) - Section/Unit/Lesson 树 + Provider + Drift + Freezed + auto_route 骨架。
- 复习算法：[fsrs](https://pub.dev/packages/fsrs)（FSRS）、SM-2（SuperMemo 2）。
- TTS：[flutter_tts](https://pub.dev/packages/flutter_tts)。
- 持久化：[drift](https://pub.dev/packages/drift) + [streaming_shared_preferences](https://pub.dev/packages/streaming_shared_preferences)。
- DI / 路由：[get_it](https://pub.dev/packages/get_it) + [injectable](https://pub.dev/packages/injectable) + [auto_route](https://pub.dev/packages/auto_route)。
- Anki 保真：[webview_flutter](https://pub.dev/packages/webview_flutter)。

---

## License

见 [LICENSE](./LICENSE)。
