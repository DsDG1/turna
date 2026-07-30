# Varnamala Plus — Code Wiki

> 本仓库的完整结构化 Code Wiki 文档。涵盖项目整体架构、主要模块职责、关键类与函数说明、依赖关系以及项目运行方式。

---

## 文档导航

| 文档 | 内容 |
|---|---|
| [01. 项目概览](./01-overview.md) | 项目定位、设计哲学、教学法基础、技术栈、当前内容状态 |
| [02. 整体架构](./02-architecture.md) | 分层架构、模块职责、关键设计模式、初始化流程 |
| [03. 领域层（Domain）](./03-domain-layer.md) | 课程模型、Freezed 数据类、Repository 接口 |
| [04. 应用层（Application / Providers）](./04-application-layer.md) | 全部 ChangeNotifier、SRS 队列、统计聚合、状态管理 |
| [05. 数据层（Data）](./05-data-layer.md) | Drift SQLite Schema、DAO、Repository 实现、Seeder |
| [06. UI 层（Views）](./06-views-layer.md) | 路由树、底部导航、各功能页面与组件 |
| [07. SRS / 间隔重复引擎](./07-srs-engine.md) | FSRS 算法、SM-2 回退、复习调度、错题本 |
| [08. AI 引擎与编辑器](./08-ai-engine.md) | AI 课程生成、AI 提示、教材导入、GUI 编辑器 |
| [09. 核心工具与扩展](./09-core-and-utils.md) | Core 工具、SRS 调度器、扩展、工具类 |
| [10. 依赖关系与第三方库](./10-dependencies.md) | pubspec 解析、关键依赖图、平台适配 |
| [11. 构建与运行](./11-build-and-run.md) | 开发命令、Makefile、构建流水线、测试 |
| [12. Varnamala GUI 课程编辑器](./12-tool-gui.md) | PySide6 桌面编辑器、CourseAdapter、AI 流水线、测试与打包 |
| [13. Experience AI 中枢神经系统](./13-experience-ai.md) | L0–L6 深度融合、Context Bus、Intent Router、Planner、Policy、Patch、Focus Ring、A3 Ambient、Sovereign 探索稿 |

---

## 项目一句话总结

**Varnamala Plus** 是一个基于 Flutter 的本地优先、离线语言学习应用框架，当前以 **Turkish（土耳其语）** 为主目标语。框架围绕 *Section → Unit → Lesson → Stage → Interaction* 的层次化课程模型，搭配 **SM-2/FSRS** 间隔重复引擎、错题本、匹配游戏、AI 助教等学习闭环。无云后端、无社交、无变现机制；全部学习数据通过 **drift (SQLite)** + **SharedPreferences** 存储在本地。

---

## 项目主要特征

### 功能维度

- **8 个 CEFR 分级 Section**（A1→B2），含 inter-section 前置依赖
- **6 种 Lesson Template**（intro / practice / listening / reading / review / mastery）
- **13 种 Interaction 题型**（showWord / multipleChoice / multiSelect / fillBlank / translateSentence / reorderSentence / typeTheWord / listenAndPick / listenOnly / readingMcq / readingTrueFalse / readingShortAnswer 等）
- **SRS 间隔重复**：SM-2（保留）+ FSRS（生产默认，ADR 0028）
- **错题本**：30 条 FIFO，含原始 interaction 快照
- **弱词复习**：30 天内错误 ≥2 次的词自动汇聚为 10 题 quiz
- **每日挑战**：从课程树随机抽题，模拟交错练习
- **Match Madness**：限时单词配对小游戏
- **AI 提示**：课程内嵌 AI 聊天面板，支持任意 OpenAI-compatible endpoint
- **教材导入**：从 PDF / Word / 图片 / 文本多阶段提取
- **本地每日提醒**：`flutter_local_notifications`

### 工程维度

- **Clean Architecture** + **Provider/ChangeNotifier**
- **GetIt + Injectable** 依赖注入（DI 模块化）
- **Auto Route** + 代码生成 + `CourseReadyGuard`
- **Freezed** 不可变模型 + JSON 序列化
- **Drift (SQLite)** + DAO/Repository 模式
- **PySide6 GUI 编辑器**（`tool/gui/`）：可视化编辑课程 JSON
- **生成代码已提交到版本库**，新克隆无需运行 `build_runner`
- **支持 Android / iOS / Windows / macOS / Linux / Web / OHos（鸿蒙）**

---

## 快速入口

- **App 入口**：[`lib/main.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/main.dart)
- **根 Widget**：[`lib/views/app.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/app.dart)
- **路由配置**：[`lib/routing/routing.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/routing/routing.dart)
- **DI 入口**：[`lib/di/injection.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/di/injection.dart)
- **Provider 列表**：[`lib/application/providers.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/providers.dart)
- **课程模型根**：[`lib/domain/course/lesson.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson.dart)
- **数据库 Schema**：[`lib/data/course_database.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart)

---

## 项目元信息

- **仓库名**：Varnamala Plus
- **当前版本**：`1.0.0+1`（[`pubspec.yaml`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/pubspec.yaml)）
- **目标语言**：Turkish（ADR 0020）
- **数据库 Schema 版本**：v8（含 `expressions` 表、`srs_states` 表、Anki 导入、FSRS 字段）
- **平台**：Android / iOS / Windows / macOS / Linux / Web / OHos（鸿蒙）
- **Dart SDK**：`>=3.2.3 <4.0.0`
- **作者工具**：[`tool/gui/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/)（PySide6）