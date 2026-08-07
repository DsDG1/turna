# Turna 项目框架分析（产品 / 用户视角）

> 本文档从**产品经理、用户研究员和潜在运营者**的视角，对 Turna 的产品定位、功能结构、学习闭环、技术底座与商业化边界进行系统梳理。**不涉及课程内容填充度评估**，只关注框架能力、用户体验路径与产品决策。
>
> 更新：2026-08-07。工程实现细节以 [`docs/project-guide.md`](../project-guide.md) 为准；本文为产品/框架视角的概览。

---

## 1. 一句话定位

Turna 是一款**本地优先、离线可用、类 Duolingo 体验的语言学习应用框架**，当前以土耳其语为默认目标语言，强调：

- 无账号、无社交、无内购的**纯净学习体验**；
- 由课程树、13 种题型、FSRS 复习、错题/弱词回顾、每日提醒、成就与装饰系统构成的**完整学习闭环**；
- 基于 JSON 课程内容的**可扩展多语言框架**，并打通 Anki 牌组导入与统一 AI 引擎层。

---

## 2. 目标用户与使用场景

| 维度 | 描述 |
|------|------|
| **核心用户** | 希望自学土耳其语（或后续扩展语言）的成人/青年学习者，偏好无干扰、离线可用的移动学习。 |
| **使用场景** | 通勤、睡前 10–15 分钟碎片化学习；以连续打卡（Streak）和成就/装饰系统维持动力。 |
| **用户痛点** | 不想注册账号、反感广告/内购/体力系统、需要听力输入与错题复习、希望导入自有 Anki 牌组。 |
| **价值主张** | "打开即学，学完即走，离线也能保持学习进度；可导入 Anki 牌组、由 AI 辅助生成内容。" |

---

## 3. 核心架构：一个可扩展的"学习引擎"

### 3.1 技术栈

- **Flutter 跨平台**：Android / iOS / HarmonyOS（OHOS Flutter 分支）/ Web（有限）。基于 OpenHarmony Flutter fork（`3.35.8-ohos`），非官方 Flutter。
- **状态管理**：Provider + ChangeNotifier。
- **依赖注入**：GetIt + Injectable，服务/Provider 均可被替换、方便测试。
- **路由**：Auto Route，带 `CourseReadyGuard` 保证课程数据加载前不进入主界面。
- **本地数据**：Drift/SQLite（schemaVersion 16）存储课程元数据、内容、Anki NoteStore、SRS 状态与复习历史；StreamingSharedPreferences 存储用户偏好；AI API key 经 `flutter_secure_storage` 存储。
- **复习引擎**：FSRS（`lib/core/fsrs_engine.dart`），SM-2 作为后备调度器；记忆曲线可视化与 FSRS 参数优化。
- **音频**：`flutter_tts` 系统 TTS（语言码 `tr`，Android 优先 Google TTS）；`AudioController` 统一接管 TTS 与音效；智能朗读按脚本自动检测语言。
- **AI**：统一 AI 引擎层（`lib/application/ai/engine/`）+ AI Hub，支持流式/取消/缓存/严格 schema。
- **Anki 保真**：`webview_flutter` 渲染原 notetype HTML/CSS（仅 Android/iOS，其余平台文本兜底）。
- **构建/发布**：`tool/build_release.py` 一键生成 APK/AAB/可选 web + 内容清单。

### 3.2 分层结构（产品可理解版）

```
用户层（Views）        -> 课程树、学习页、Play Hub、个人资料、设置、词典、AI Hub、Anki 复习
应用层（Application）  -> Provider/ViewModel：课程、学习、SRS(FSRS)、错题、成就、统计、记忆曲线、
                          AI 引擎与 companion、Anki 导入/渲染、主题、可访问性
领域层（Domain）       -> 课程/学习/音频/Anki 等领域的模型与接口
数据层（Data）          -> drift SQLite（课程 + Anki NoteStore + SRS 状态/复习历史）+ SharedPreferences 学习日志
课程内容层（Courses）   -> 资产目录中的 JSON 课程数据（index.json + section + vocab/expression/grammar）
```

产品意义：

- **课程内容是数据资产**：新增语言或调整课程只需改 JSON 与资源，无需改代码。
- **用户状态本地可迁移**：进度、错题、SRS 状态都在本地，可在 Settings 页导出/导入 JSON 备份。
- **测试友好**：ViewModel 与 Repository 解耦，便于自动化回归（~937 测试）。

---

## 4. 功能模块地图

### 4.1 主导航

底部导航采用 **Learn / Play / Profile** 三段式：

| Tab | 承载内容 | 产品意图 |
|-----|----------|----------|
| **Learn** | 课程树（`lib/views/courses/course_tree.dart`） | 核心学习路径，展示章节/单元/课程，显式进度、到期、薄弱标识。 |
| **Play** | Play Hub（`lib/views/play/play_hub_screen.dart`） | 把"复习/游戏化"入口集中，并作为 AI Hub 入口。 |
| **Profile** | 个人资料（`lib/views/profile/profile_screen.dart`） | 展示成就、学习统计、记忆曲线、连续打卡，强化自我反馈。 |

### 4.2 学习页：统一题型渲染器

课程页通过 `LessonViewModel` 驱动，所有题型被抽象为统一的 `Interaction`（13 种，`@injectable` 插件注册）：

- 词汇呈现：`showWord`
- 接受性词汇：`multipleChoice` / `multiSelect`
- 产出性句法：`fillBlank` / `translateSentence` / `reorderSentence` / `typeTheWord`
- 听力：`listenAndPick` / `listenOnly`
- 阅读：`readingMcq` / `readingTrueFalse` / `readingShortAnswer`
- Anki 保真：`ankiHtmlCard`

6 种 Lesson Template（intro / practice / listening / reading / review / mastery，另含 `legacy` 兜底）。新增题型无需改 LessonViewModel，只需新增 Renderer。

### 4.3 课程结构：模板化而非硬编码

课程采用 **Section -> Unit -> Lesson -> SubLesson / ListeningPhase / ReadingPassage -> Stage -> Interaction** 层级；`LessonTemplate` 定义模板，所有 lesson 最终展平为 `List<Stage>`，渲染层无感知。8 个 CEFR 分级 Section（A1->B2）全部填充真实内容（148 词汇 / 18 表达 / 8 语法点 / 54 课时，每节含听力与阅读）。

### 4.4 Play 中心：复习、游戏化与 AI 入口

Play Hub 把分散的复习入口统一（轻量 `SoftCard` 视觉），包含：

| 入口 | 机制 | 触发条件 |
|------|------|----------|
| **Quick Play (Match Madness)** | 限时单词配对小游戏 | 随时可玩，补充 XP 与趣味。 |
| **My Mistakes** | 最近 30 条错题 FIFO 队列 | 做错即记录，可逐条重写。 |
| **Review (SRS)** | 基于 FSRS 的单词/表达卡片复习 | 到期的卡片出现。 |
| **Grammar Review** | 语法点 SRS 复习（Explain -> Practice -> Rate） | 语法点到期或做错相关题后标记为到期。 |
| **Daily Challenge** | 随机抽题合成挑战课 | 每日一次，交错练习。 |
| **Weak Words** | 30 天内错 ≥2 次的单词生成 10 题小测 | 动态 assembled lesson。 |
| **Dictionary** | 搜索单词/表达/语法并播放发音 | 随时查阅。 |
| **AI Hub** | 统一 AI 入口（许愿生成/教材导入/SRS 导师/深度讲解） | 从 Play Hub 进入。 |

### 4.5 个人资料、成就与装饰

`ProfilePage` 展示：

- 连续打卡（Streak）、总 XP、宝石；
- 学习统计仪表盘：今日 XP/学习时长/准确率、近 7 天 XP 趋势、累计统计、弱词分析；
- 记忆曲线：当前保持率（R=exp(-Δt/S)）、到期预测、成熟度分布、按间隔分桶的经验回忆率曲线；
- 成就体系（多阶段：Scholar / Sage / Wildfire / Champion / Sharpshooter / Winner）；
- 装饰系统：宝石可兑换头像环（晨雾/芦苇/湖光），`CosmeticProvider` 管理。

成就与装饰体系设计了阶梯目标与纯装饰消耗，符合自我决定理论中的"胜任感"与"进度可视化"，且不引入付费压力。

---

## 5. 用户体验闭环：从打开到持续学习

### 5.1 启动流程

1. **Splash**：品牌露出，检测 TTS 可用性（土耳其语语音包缺失时引导安装）。
2. **主界面初始化**：检查连续打卡、同步宝石/成就、内容版本升级时提示重置进度。
3. 进入 **Learn Tab**，课程树加载当前章节。

### 5.2 学习流程

```
选择课程 -> 进入学习页 -> 逐题作答 -> 提交 -> 正确：升级音效 + 自动/手动下一题
                                        -> 错误：错误音效 + 记录错题 + 显示"Got It"
                ↓
          完成课程 -> 结算弹窗（XP / 宝石 / 是否 Perfect）-> 更新课程树状态
                -> 触发完成协调器：发放 XP（含 Perfect 加成）/ 宝石、记录完成、检查成就、写学习日志
```

### 5.3 复习流程

- 单词/表达在课程中首次出现即进入 SRS 队列；
- 用户通过 Review / SRS Review 界面按 FSRS 复习（目标保持率 0.9）；
- 回答质量影响下次到期时间，失败走当日重学阶梯；
- 错题通过 My Mistakes 与 Weak Words 两条路径被重新练习；
- Anki 牌组导入后，到期 Anki 卡走保真复习（Show Answer -> Again/Hard/Good/Easy）。

### 5.4 持续动力机制

| 机制 | 说明 |
|------|------|
| **XP** | 课程完成与 Perfect 加成；SRS / Grammar Review 每次奖励。 |
| **Streak** | 每日首次学习即延长连续天数；断签后归零并提示。 |
| **Gems** | 完成课程/Perfect/解锁成就奖励宝石；宝石可兑换头像环装饰（`GemsProvider.spendGems`）。 |
| **Perfect 课程** | 课程全对标记为 Perfect，课程树显示标记。 |
| **课程树状态徽章** | 已完成 / 有到期复习 / 薄弱标识。 |
| **本地每日提醒** | 可设置固定时间本地通知，提醒学习（无 streak repair）。 |

---

## 6. 数据与持久化策略

### 6.1 课程数据：JSON + SQLite 缓存

- 原始课程文件位于 `assets/courses/turkish/`（内容版本 12）；
- 应用首次启动由 `DatabaseSeeder` 解析 JSON 写入 SQLite（schemaVersion 16）；
- `CourseRepository` 支持"章节外壳轻量加载 + 课程正文按需加载"（L1/L2 分离）；
- 内容版本变化时触发 reseed，并对已有进度的用户提示"保留或重置进度"。

### 6.2 用户状态

| 数据类型 | 存储方式 | 说明 |
|----------|----------|------|
| 分数、连续打卡、完成课程、宝石、成就、主题、设置 | SharedPreferences | 轻量，读取频繁。 |
| SRS 状态（单词/表达/语法点） | SQLite `SrsStates` 表 | write-through 持久化，启动水合。 |
| 复习历史 | SQLite `ReviewEvents` 表 | 每次评分写一条，带索引。 |
| 错题日志 | SharedPreferences JSON，FIFO 30 条 | `MistakeProvider` 管理。 |
| 学习日志 / 每日统计 | SharedPreferences + 追加策略 | 近期队列 + 主日志合并。 |
| AI 配置（含 API key） | flutter_secure_storage（key）+ SharedPreferences（非敏感元数据） | 绕过日志。 |
| Anki NoteStore | SQLite `anki_notetypes` / `anki_notes` / `anki_cards_meta` | 导入牌组的主数据。 |

### 6.3 数据安全与隐私

- 完全离线，无后端、无账号、无遥测；
- 全局错误处理仅本地记录（`SystemHealthMonitor` 监控 `LogCapture` 生成本机告警），不发送到服务器；
- 无 Google/Facebook 登录，无排行榜，无社交数据；
- 进度导出 JSON 不含 AI API key。

---

## 7. 学习与复习机制深度解析

### 7.1 SRS：FSRS 引擎

- `lib/core/fsrs_engine.dart` 基于 [fsrs](https://pub.dev/packages/fsrs) 包，以目标保持率（默认 0.9）驱动下次间隔；
- 失败走当日重学阶梯（`fsrs_relearn.dart`）；可选参数优化（`fsrs_optimizer.dart`）按个人复习历史拟合权重；
- SM-2（`lib/core/sm2.dart`）作为后备调度器保留；
- 支持单词、表达、语法点三类 SRS 队列；复习界面提供自评（Again/Hard/Good/Easy）。

### 7.2 记忆曲线

`MemoryCurveProvider` 计算当前保持率、到期预测、成熟度分布与按间隔分桶的经验回忆率曲线；Profile 页用 `fl_chart` 可视化。

### 7.3 错题与弱词

- 每道题做错即记录一条 `MistakeEntry`，保存错题快照、用户答案、正确答案、时间戳；
- `MistakeListPage` 可查看并重写；
- `WeakWordQuizAssembler` 把 30 天内错 ≥2 次的单词动态组装成 10 题小测。

### 7.4 每日挑战

从已加载课程中随机抽取真实题项合成挑战课，复用 LessonViewModel，实现跨题型跨单元的交错练习。

### 7.5 Anki 深度集成

直接导入 `.apkg` 牌组作为课程树的一个 Section，与 SRS / 错题 / 统计双向打通：

- 解析 -> NoteStore 持久化 -> 装配为 Section/Unit/Lesson -> 媒体拷贝 -> revlog 迁移为复习历史（FSRS 调度）；
- 智能组织（按 notetype 字段名抽取 unit/lesson 键）、9 种 notetype 映射（可编辑 + AI 智能识别）；
- Full / Lite 模式（<2k 卡建完整树，≥2k 卡仅 shell Section）；
- 保真渲染（WebView 渲染原 HTML/CSS）+ 智能去解密（加密牌组首次跑 JS 后缓存纯 HTML）；
- Anki 式复习（Show Answer -> 四按钮）。

详见 [`docs/anki-deep-adaptation-plan.md`](../anki-deep-adaptation-plan.md) 与 [`docs/anki-official-alignment-remediation-plan.md`](../anki-official-alignment-remediation-plan.md)。

---

## 8. AI 能力

统一 AI 引擎层（`lib/application/ai/engine/`）是全应用唯一 LLM 出入口：双模型配置（chat / JSON）+ 严格 schema 模式 + 流式/取消 + SHA-256 缓存 + 预设（deepseek 默认 / openai / moonshot / ollama / custom）。集中入口为 **AI Hub**。

| 功能 | 说明 |
|------|------|
| **AI 提示助手** | 课程内聊天面板，按当前题目上下文给提示与解释。 |
| **深度讲解** | 4 种 genre：语法讲解 / 近义词辨析 / 句子拆解 / 错因分析。 |
| **SRS 导师** | 据错题 + 弱词 + 近期复习，AI 生成复习课写入课程树。 |
| **许愿生成** | 多轮对话对齐需求 + 附件 -> 滑动确认生成 section JSON + 通俗解释。 |
| **教材导入** | 从 PDF/Word/图片/文本提取词汇/表达/语法点，多阶段向导导入。 |
| **课程生成** | 普通/许愿模式；`ai_fixer` 自动修复 id 冲突/引用断裂/schema 不符。 |

安全姿态：API key 经 `flutter_secure_storage` 持久化（可选不保存），写入绕过日志；附件用临时文件；进度导出不含 key。详见 [`docs/ai_companion_implementation.md`](../ai_companion_implementation.md) 与 ADR 0034。

---

## 9. 主题与可访问性

- **TurnaTheme**（`lib/views/theme.dart`）：亮 / 暗 / 高对比变体 + 语义化颜色 helper；调色板为 Turna「湿地鹤」（ADR 0033 方案 A，主色 `#1F727E` 锁死；ADR 0035 去绿化重锚 `brandReed`）；Play Hub 用轻量 `SoftCard`。
- **AccessibilityProvider**：6 项持久化偏好--文本缩放 100–200%、减少动画、高对比、阅读障碍字体（Lexend）、感官减负、专注模式。
- Settings 7 大类：Account / Learning / Audio & Haptics / Accessibility / AI Tools / Data / About。

---

## 10. 产品化边界与决策取舍

### 10.1 已明确移除的功能

相比 Duolingo，团队**主动做减法**，避免免费应用常见的商业化摩擦：

- ❌ 账号/登录/云同步
- ❌ 排行榜、联赛、好友、社交成就
- ❌ 体力/生命值系统
- ❌ 内购、宝石购买、付费道具
- ❌ 连签修复、周末护符
- ❌ 推送通知（仅保留本地提醒）
- ❌ 语音识别/口语评分（TTS 替代）

> 注：宝石**可消耗**于纯装饰性头像环（`CosmeticProvider`），但**不可购买**--无付费入口，保持无摩擦。

### 10.2 这一取舍的产品意义

- **优势**：体验纯粹、无付费压力、用户留存不依赖 FOMO 机制；适合教育公益、家长放心、隐私敏感用户。
- **劣势**：缺少社交激励、无订阅变现、无法跨设备同步进度、对"成就驱动型"用户吸引力可能不足。

### 10.3 当前商业化可能性

由于代码层面没有内购、广告、订阅，当前产品形态更接近**开源/公益教育工具**或**内容分发框架**。若未来商业化，需新增云同步与账号体系、付费课程包/订阅、家庭/教师账户，或保持免费通过课程授权/内容合作变现。

---

## 11. 工程与产品质量亮点

| 亮点 | 产品影响 |
|------|----------|
| **无广告/无内购的本地优先架构** | 用户无需网络、无需账号即可学习。 |
| **内容-代码分离 + GUI 编辑器** | `tool/gui`（PySide6）提供教师视图、教材导入、AI 生成、Workshop；教研团队可独立生产课程。 |
| **题型与渲染器解耦** | 新增题型无需改核心流程，降低创新成本。 |
| **FSRS + 记忆曲线** | 以目标保持率驱动调度，比传统 SM-2 更贴近真实遗忘曲线，并向用户可视化保持率。 |
| **Anki 生态打通** | 可导入自有牌组并保真复习，吸纳 Anki 现有用户存量。 |
| **统一 AI 引擎层** | 所有 LLM 流量单一出入口，便于缓存/取消/安全控制。 |
| **可访问性** | 6 项持久化偏好 + 高对比主题 + 语义标签 + 对比度适配。 |
| **测试与发布流水线** | ~937 Flutter 测试 + Python 工具/GUI 测试 + golden 测试 + 一键打包（`tool/build_release.py`）。 |
| **ADR 文档化** | 现存 ADR 0030–0035（`docs/decisions/`），降低团队交接与长期维护成本。 |

---

## 12. 关键文件索引

| 关注点 | 关键文件 |
|--------|----------|
| 入口与启动 | `lib/main.dart`、`lib/views/app.dart` |
| 路由与守卫 | `lib/routing/routing.dart`、`lib/routing/course_ready_guard.dart` |
| 状态/依赖注入 | `lib/di/injection.dart` |
| 课程树 | `lib/views/courses/course_tree.dart` |
| 学习页 | `lib/views/lesson/`、`lib/application/lesson_viewmodel.dart` |
| 题型模型 | `lib/domain/course/interaction.dart` |
| Play Hub | `lib/views/play/play_hub_screen.dart` |
| SRS（FSRS） | `lib/core/fsrs_engine.dart`、`lib/application/srs_provider.dart` |
| 记忆曲线 | `lib/application/memory_curve_provider.dart` |
| 错题 | `lib/application/mistake_provider.dart` |
| 弱词 | `lib/application/weak_word_quiz_assembler.dart` |
| 统计 | `lib/application/study_stats_provider.dart`、`lib/views/profile/widgets/learning_stats.dart` |
| 成就/装饰 | `lib/application/achievements_provider.dart`、`lib/domain/cosmetics/` |
| Anki | `lib/application/anki/`、`lib/data/anki_note_dao.dart` |
| AI 引擎 | `lib/application/ai/engine/` |
| 数据仓库 | `lib/data/course_repository.dart`、`lib/data/study_log_repository.dart` |
| 音频 | `lib/application/audio_controller.dart`、`lib/core/language_detector.dart` |
| 主题 | `lib/views/theme.dart` |
| GUI 编辑器 | `tool/gui/` |

---

## 13. 风险与改进建议（产品视角）

### 13.1 当前风险

| 风险 | 说明 |
|------|------|
| **TTS 依赖系统语音包** | 土耳其语语音包未安装时，splash 会引导用户安装，过程可能劝退部分用户。 |
| **无跨设备同步** | 换机/重装后进度丢失（可手动导出/导入 JSON），影响长期用户留存。 |
| **Anki 保真平台差异** | WebView 保真仅 Android/iOS；HarmonyOS/Web/桌面降级为文本兜底。 |
| **AI 依赖外部 key** | AI 功能需用户自配 API key，门槛较高；未配置时功能不可用。 |

### 13.2 改进方向

1. **内容深化**：8 节已有真实内容，后续按语料词频与 CEFR 语法渐进持续扩充深度与覆盖度。
2. **Anki 二期**：review-ops（undo/suspend/bury/flag）、per-deck stats/browser/export、`{{type:}}` 输入桥、OHOS import sqlite3 FFI。
3. **数据导出/导入体验**：强化进度备份与跨设备迁移的易用性。
4. **多语言入口**：利用现有框架增加语言选择页，展示"更多课程即将到来"。
5. **教师/班级模式**：利用学习统计与错题数据，提供教师端查看学生进度（离线导出报告）。

---

## 14. 结论

Turna 已经构建了一个**成熟、可扩展、测试充分、产品边界清晰**的语言学习框架，并在三个方向上持续深化：FSRS 复习引擎、Anki 牌组导入与高保真渲染、统一 AI 引擎层。它在"类 Duolingo 体验"与"去商业化、离线、隐私优先"之间做出了明确取舍，适合作为：

- 面向特定语言（如土耳其语）的教育公益应用；
- 内容驱动型语言课程的分发平台；
- 后续引入账号/云同步/订阅后的商业化产品基础。

后续最大的产品工作将从**工程框架建设**转向**课程内容深化、Anki/AI 能力打磨与用户增长**。

---

*文档更新：2026-08-07*
*分析范围：代码框架与产品体验，不包含课程具体内容填充度评估。*
