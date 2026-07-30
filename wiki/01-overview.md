# 01. 项目概览

## 1.1 项目定位

**Varnamala Plus** 是一个基于上游 [Varnamala](https://github.com/rshrc/Varnamala) 骨架的本地优先、离线 Flutter 语言学习应用框架。当前以 **Turkish（土耳其语）** 为主目标语，专注内容精简与深化。

> **上游**：原版骨架来自 [rshrc/Varnamala](https://github.com/rshrc/Varnamala)，本仓库为非官方定制版本。

### 核心约束

- **纯本地**：SQLite（drift），无云后端 / 推送 / 登录
- **单人离线**：无好友、排行榜、联赛、心数、宝石
- **AI 辅助开发**：所有工程决策记录在 `docs/decisions/`（ADR 0001–0020+）
- **JSON 是课程内容唯一真理源**：可视化 GUI 编辑器只是 JSON 的前端

## 1.2 教学法基础

本项目的课程设计与复习机制建立在二语习得（SLA）与认知心理学研究的基础上。

### 1.2.1 Krashen 的可理解输入（i+1）

Stephen Krashen 的**输入假说**认为语言习得发生在学习者接触到略高于当前水平的**可理解输入**（comprehensible input）时。本项目通过 CEFR 分级 Section（A1→B2）与 inter-section 前置依赖将这一原则工程化：学习者必须在较低等级达到一定掌握程度后，才能解锁下一等级内容。

### 1.2.2 Ebbinghaus 遗忘曲线与间隔重复

Hermann Ebbinghaus 在 1885 年描述了**遗忘曲线**：新记忆在形成后迅速衰减，但每次**主动检索**（active retrieval）都能显著减缓衰减。**间隔重复**（spaced repetition）将复习安排在遗忘临界点附近，以最少的复习次数达成最长的记忆保持。

- 词汇 SRS：SM-2 / **FSRS**（生产默认）
- 语法点 SRS：同 SM-2 / FSRS
- 错题本：30 条 FIFO + 弱词 quiz

### 1.2.3 测试效应（Roediger & Karpicke, 2006）

相对于被动重读，主动从记忆中提取信息（自我测试）能显著增强长期记忆保持。本项目的填空、翻译、听写、选择等多种题型本质上是不同形式的检索练习，而非单纯的"考核"。

### 1.2.4 多技能整合

应用语言学将语言能力分解为：
- **接受性技能**：听、读
- **产出性技能**：说、写
- **语言知识维度**：词汇、语法、语音

本项目通过 **6 种 Lesson Template** + **13 种 Interaction 题型** 覆盖完整学习闭环，避免孤立训练单一技能。

## 1.3 Turkish 的特殊考量

Turkish 属于**突厥语系**，是一种**黏着语**（agglutinative language）：语法关系通过向词根依次附加词缀来表达，一个词可以承载相当于英语一整句的信息。

- **元音和谐**（vowel harmony）：词缀的元音必须与词根元音在舌位前后与唇形圆展上保持一致
- **SOV 语序**：主语—宾语—动词，与汉语（SVO）、英语（SVO）语序不同
- **无语法性别**：无冠词、无名词类别，代词无性别区分

这些特征对汉语母语学习者既有门槛（语序差异、黏着形态），也有便利（无性别、拼读规则高度一致）。本项目针对这些特点设计了渐进式的语法复习流程与丰富的词形变化练习。

## 1.4 技术栈总览

### 1.4.1 核心框架

| 类别 | 技术 |
|---|---|
| 语言 | Dart `>=3.2.3 <4.0.0` |
| UI 框架 | Flutter（Material 3 + Cupertino） |
| 状态管理 | Provider + ChangeNotifier |
| 依赖注入 | GetIt + Injectable |
| 路由 | Auto Route + 代码生成 |
| 数据模型 | Freezed + json_serializable |
| 持久化 | Drift (SQLite) + StreamingSharedPreferences |
| AI 引擎 | 自研 `AiEngine`（OpenAI-compatible） |
| SRS | FSRS（生产） + SM-2（测试/回退） |

### 1.4.2 多平台支持

| 平台 | 状态 |
|---|---|
| Android | ✅ 主要目标 |
| iOS | ✅ |
| Web | ✅ |
| Windows | ✅ |
| macOS | ✅ |
| Linux | ✅ |
| OHos（鸿蒙） | ✅（通过 dependency_overrides 适配） |

## 1.5 当前内容状态（ADR 0020）

- **目标语言**：Turkish（`language: "tr"`）
- **TTS 语言代码**：`tr`（ADR 0020 取代原 `sw` 决策）
- **Section 1**（A1 入门）：含真实 Turkish 问候语单元（8 词 + 2 表达）
- **Sections 2–8**（A1 高阶→B2）：占位课程（AI 生成）
- **CEFR 等级覆盖**：A1, A2, B1, B2（4 等级 6 级未覆盖 C1/C2）

详见 [`docs/content_inventory_current.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/docs/content_inventory_current.md)。

## 1.6 已完成 vs. 不做

### 已完成（功能维度）

- [x] 课程树（Section → Unit → Lesson）+ 渐进解锁
- [x] 13 种 Interaction 题型（多选/翻译/填空/听/读/排序/多选等）
- [x] SRS 引擎（SM-2 + FSRS）+ 复习 UI
- [x] 错题本（FIFO + 原始快照）
- [x] 弱词复习（30 天 / ≥2 错）
- [x] 每日挑战（交错练习）
- [x] Match Madness 单词配对游戏
- [x] XP / 分数系统
- [x] 连胜（Streak）追踪
- [x] 暗色 / 亮色 / 跟随系统主题
- [x] 学习统计仪表盘（90 天 StudyLog + 7 日 XP 趋势）
- [x] 词典 / 搜索
- [x] 本地每日提醒（`flutter_local_notifications`，无 streak repair）
- [x] AI 提示助手 / AI 课程生成器（OpenAI-compatible）
- [x] Anki 导入 / 复习
- [x] 教材导入（PDF/Word/图片/文本）
- [x] 内容更新提示（检测 bundle 版本变化）
- [x] 可访问性（tooltip、屏幕阅读语义、高对比度、字体缩放）
- [x] 进度导出 / 导入
- [x] 发布流水线（`tool/build_release.py`）

### 明确不做（经过考量的教学决策）

- ❌ **League / 好友 / 排行榜 / 分享**：社会比较会抑制内在动机（Deci & Ryan, 1985）
- ❌ **Hearts / Streak Repair / 商店道具**：惩罚机制会诱发"失败恐惧"，导致回避高难度内容
- ❌ **Speaking 录音匹配**：自动语音评分对 Turkish 等非主流语种效度不足；TTS + 听力已覆盖语音训练
- ❌ **云端 CMS / Firebase / 推送通知**：本地优先保证离线可用与数据隐私
- ❌ **GUI 替代 JSON 作为真理源**：JSON 始终是唯一权威存储格式

## 1.7 仓库目录速览

```
Varnamalaplus/
├── assets/courses/turkish/      # Turkish 课程 JSON（唯一真理源）
├── docs/                          # 设计文档、ADR、内容清单
├── lib/                           # 应用源代码
│   ├── application/               # Providers (ChangeNotifier)
│   ├── core/                      # 枚举、SM-2/FSRS、调度器、扩展
│   ├── courses/                   # 字母 + 语种 loader/validator
│   ├── data/                      # Drift DB + DAO + Repository
│   ├── di/                        # GetIt + Injectable
│   ├── domain/                    # 领域模型 + Repository 接口
│   ├── gen/                       # 资源生成代码（flutter_gen）
│   ├── l10n/                      # 国际化字符串
│   ├── routing/                   # Auto Route 配置 + Guards
│   ├── service/                   # AppPrefs、TTS、本地提醒
│   ├── utils/                     # 工具（OHos 文件选择器）
│   └── views/                     # UI 层
├── linux/ macos/ windows/ web/    # 各平台构建配置
├── ohos/                          # 鸿蒙平台适配
├── test/                          # Dart + Python 测试
├── tool/                          # Python 工具链
│   ├── gui/                       # PySide6 课程编辑器
│   ├── course_cli.py              # 课程校验 / lint / 转换
│   ├── build_release.py           # 发布构建
│   ├── generate_audio.py          # MiniMax TTS 音频生成
│   └── mix_listening_a1.py        # 听力音频混音
├── android/ ios/                  # 原生平台配置
├── pubspec.yaml                   # 依赖声明
├── Makefile                       # 构建自动化
└── README.md / CLAUDE.md          # 项目文档
```