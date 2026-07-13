# Varnamala 项目框架分析（产品 / 用户视角）

> 本文档从**产品经理、用户研究员和潜在运营者**的视角，对 Varnamala 的产品定位、功能结构、学习闭环、技术底座与商业化边界进行系统梳理。**不涉及课程内容填充度**，只关注框架能力、用户体验路径与产品决策。

---

## 1. 一句话定位

Varnamala 是一款**本地优先、离线可用、类 Duolingo 体验的语言学习应用框架**，当前以土耳其语为默认目标语言，强调：

- 无账号、无社交、无内购的**纯净学习体验**；
- 由课程树、多种题型、SRS 复习、错题/弱词回顾、每日提醒、成就系统构成的**完整学习闭环**；
- 基于 JSON 课程内容的**可扩展多语言框架**。

---

## 2. 目标用户与使用场景

| 维度 | 描述 |
|------|------|
| **核心用户** | 希望自学土耳其语（或后续扩展语言）的成人/青年学习者，偏好无干扰、离线可用的移动学习。 |
| **使用场景** | 通勤、睡前 10–15 分钟碎片化学习；以连续打卡（Streak）和成就系统维持动力。 |
| **用户痛点** | 不想注册账号、反感广告/内购/体力系统、需要听力输入与错题复习。 |
| **价值主张** | “打开即学，学完即走，离线也能保持学习进度。” |

---

## 3. 核心架构：一个可扩展的“学习引擎”

### 3.1 技术栈

- **Flutter 跨平台**：一套代码同时覆盖 Android / iOS / Web / Windows / macOS。
- **状态管理**：Provider + ChangeNotifier，轻量且适合中高频学习交互。
- **依赖注入**：GetIt + Injectable，服务/Provider 均可被替换、方便测试。
- **路由**：Auto Route，带 `CourseReadyGuard` 保证课程数据加载前不进入主界面。
- **本地数据**：Drift/SQLite 存储课程元数据与内容；StreamingSharedPreferences 存储用户状态（进度、SRS、错题、统计等）。
- **音频**：`flutter_tts` 系统 TTS，优先 Google TTS；`audioplayers` 播放音效与预录制音频；`VocabAudioResolver` 抽象层负责音频来源解析。
- **构建/发布**：`tool/build_release.py` 一键生成 APK/AAB/Web 与内容清单。

### 3.2 分层结构（产品可理解版）

```
用户层（Views）        → 课程树、学习页、Play 中心、个人资料、设置、词典
应用层（Application）  → Provider/ViewModel：课程、学习、SRS、错题、成就、统计、主题
领域层（Domain）       → 课程/学习/音频/游戏等领域的模型与接口
数据层（Data）          → SQLite 课程库 + SharedPreferences 学习日志
课程内容层（Courses）   → 资产目录中的 JSON 课程数据（index.json + section + vocab/expression/grammar）
```

这种分层带来的产品意义：

- **课程内容是数据资产**：新增语言或调整课程只需改 JSON 与资源，无需改代码。
- **用户状态本地可迁移**：所有进度、错题、SRS 状态都在本地，可导出/备份（当前未提供 UI）。
- **测试友好**：ViewModel 与 Repository 解耦，便于自动化回归。

---

## 4. 功能模块地图

### 4.1 主导航（底部三栏）

底部导航采用 **Learn / Play / Profile** 三段式：

| Tab | 承载内容 | 产品意图 |
|-----|----------|----------|
| **Learn** | 课程树 [CourseTree](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/courses/course_tree.dart) | 核心学习路径，展示章节/单元/课程，显式进度、到期、薄弱标识。 |
| **Play** | Play Hub [PlayHubScreen](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/play/play_hub_screen.dart) | 把“游戏化/复习”入口集中，降低用户发现成本。 |
| **Profile** | 个人资料 [ProfilePage](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/profile/profile_screen.dart) | 展示成就、学习统计、连续打卡，强化自我反馈。 |

### 4.2 学习页：统一题型渲染器

课程页 [NewLessonScreen](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/lesson/new_lesson_screen.dart) 通过 [LessonViewModel](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/lesson_viewmodel.dart) 驱动，所有题型被抽象为统一的 `Interaction`：

- **ShowWord**：词汇展示/引入；
- **MultipleChoice**：多选翻译；
- **MultiSelect**：多选（听力场景）；
- **FillBlank**：填空；
- **TranslateSentence**：句子翻译；
- **ListenAndPick / TypeTheWord / ListenOnly**：听力相关；
- **ReorderSentence**：句子重组；
- **ReadingMCQ / ReadingTrueFalse / ReadingShortAnswer**：阅读理解。

产品意义：题型数量已覆盖 Duolingo 主流形态，且新增题型无需改 LessonViewModel，只需新增 Renderer。

### 4.3 课程结构：模板化而非硬编码

课程采用 **Section → Unit → Lesson → LessonContent** 四层：

- [LessonTemplate](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/domain/course/lesson.dart#L24-L49) 定义了 intro / practice / listening / reading / review / mastery / legacy 等模板；
- 同一模板下，所有 lesson 最终都被展平为 `List<Stage>`，渲染层无感知。

这使课程设计者可像搭积木一样生产课程，而工程团队只维护题型与模板。

### 4.4 Play 中心：复习与游戏化

Play Hub 把分散的复习入口统一，包含：

| 入口 | 机制 | 触发条件 |
|------|------|----------|
| **Quick Play (Match Madness)** | 限时单词配对小游戏 | 随时可玩，补充 XP 与趣味。 |
| **My Mistakes** | 最近 30 条错题 FIFO 队列 | 做错即记录，可逐条重写。 |
| **Review (SRS)** | 基于 SM-2 的单词/表达卡片复习 | 到期的单词/表达出现。 |
| **Grammar Review** | 语法点 SRS 复习 | 语法点到期或做错相关题后标记为到期。 |
| **Daily Challenge** | 随机 15 题 | 每日一次，检测综合水平。 |
| **Weak Words** | 30 天内错 ≥2 次的单词生成小测 | 动态 assembled lesson。 |
| **Dictionary** | 搜索词汇/表达/语法并播放发音 | 随时查阅。 |

### 4.5 个人资料与成就

[ProfilePage](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/profile/profile_screen.dart) 展示：

- 连续打卡（Streak）、总 XP、宝石；
- [LearningStats](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/profile/widgets/learning_stats.dart)：今日 XP/学习时长/准确率、近 7 天 XP 柱状图、累计学习时长/准确率/课程数/复习数；
- [Achievements](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/profile/widgets/achievements.dart)：多阶段成就（Scholar / Sage / Wildfire / Champion / Sharpshooter / Winner）。

成就体系设计了阶梯目标，符合自我决定理论中的“胜任感”与“进度可视化”。

---

## 5. 用户体验闭环：从打开到持续学习

### 5.1 启动流程

1. **Splash** [SplashPage](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/splash/splash_page.dart)：品牌露出，检测 TTS 可用性（土耳其语语音包缺失时引导安装）。
2. **主界面初始化** [HomePage](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/home/home_page.dart)：检查连续打卡、同步宝石/成就、内容版本升级时提示重置进度。
3. 进入 **Learn Tab**，课程树加载当前章节。

### 5.2 学习流程

```
选择课程 → 进入 NewLessonScreen → 逐题作答 → 提交 → 正确：播放升级音效 + 自动/手动进入下一题
                                               → 错误：播放错误音效 + 记录错题 + 显示“Got It”
                     ↓
               完成课程 → 结算弹窗（XP / 宝石 / 是否 Perfect）→ 更新课程树状态
                     → 触发 LessonCompletionCoordinator：
                       - 发放 XP（含 Perfect 加成）
                       - 发放宝石
                       - 记录完成/Perfect
                       - 检查成就里程碑
                       - 写入学习统计日志
```

### 5.3 复习流程

- 单词/表达在课程中首次出现即进入 SRS 队列；
- 用户通过 Review / SRS Review 界面按 SM-2 算法复习；
- 回答质量影响下次到期时间；
- 错题通过 My Mistakes 与 Weak Words 两条路径被重新练习。

### 5.4 持续动力机制

| 机制 | 说明 |
|------|------|
| **XP** | 课程完成 10 XP，Perfect 额外 15 XP；SRS / Grammar Review 每次 5 XP。 |
| **Streak** | 每日首次学习即延长连续天数；断签后归零并提示。 |
| **Gems** | 完成课程/Perfect 奖励宝石；解锁成就也奖励 50 宝石。 |
| **Perfect 课程** | 课程全对标记为 Perfect，课程树显示皇冠。 |
| **课程树状态徽章** | 已完成（绿色对勾）、有到期复习（黄色时钟）、薄弱（红色哑铃）。 |
| **本地每日提醒** | 可设置固定时间本地通知，提醒学习。 |

---

## 6. 数据与持久化策略

### 6.1 课程数据：JSON + SQLite 缓存

- 原始课程文件位于 `assets/courses/turkish/`；
- 应用首次启动时由 [DatabaseSeeder](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/data/course_database_seeder.dart) 解析 JSON 并写入 SQLite；
- [CourseRepository](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/data/course_repository.dart) 支持“章节外壳轻量加载 + 课程正文按需加载”（L1/L2 分离），避免课程树打开时加载大量 JSON；
- 内容版本变化时触发升级/重seed，并对已有进度的用户提示“保留或重置进度”。

### 6.2 用户状态：StreamingSharedPreferences

| 数据类型 | 存储方式 | 说明 |
|----------|----------|------|
| 分数、连续打卡、完成课程、宝石、成就、主题、设置 | SharedPreferences | 轻量，读取频繁。 |
| SRS 状态（单词/表达/语法点） | SharedPreferences JSON blob | 统一由 [SrsQueueProvider](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/srs_queue_provider.dart) 基类管理。 |
| 错题日志 | SharedPreferences JSON，FIFO 30 条 | 由 [MistakeProvider](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/mistake_provider.dart) 管理。 |
| 学习日志 / 每日统计 | SharedPreferences + 追加策略 | [StudyLogRepository](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/data/study_log_repository.dart) 采用“近期队列 + 主日志合并”的写入策略，避免频繁重写整个日志。 |

### 6.3 数据安全与隐私

- 完全离线，无后端、无账号、无遥测；
- 全局错误处理仅本地记录，不发送到服务器；
- 无 Google/Facebook 登录，无排行榜，无社交数据。

---

## 7. 学习与复习机制深度解析

### 7.1 SRS：SM-2 算法

- [sm2.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/core/sm2.dart) 实现标准的 SM-2 间隔重复算法；
- 支持单词、表达、语法点三类 SRS 队列；
- 复习界面 [SrsReviewScreen](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/review/srs_review_screen.dart) 提供自评质量（Again/Hard/Good/Easy）。

### 7.2 错题与弱词

- 每道题做错即记录一条 [MistakeEntry](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/domain/course/mistake_entry.dart)，保存错题快照、用户答案、正确答案、时间戳；
- [MistakeListPage](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/review/mistake_list_page.dart) 可查看并重写；
- [WeakWordQuizAssembler](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/weak_word_quiz_assembler.dart) 把 30 天内错 ≥2 次的单词动态组装成 10 题小测。

### 7.3 每日挑战

[DailyChallengeAssembler](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/daily_challenge_assembler.dart) 从已加载课程中随机抽取 15 道可评分题目，复用 LessonViewModel，无需额外学习页面。

---

## 8. 产品化边界与决策取舍

### 8.1 已明确移除的功能

相比 Duolingo，团队**主动做减法**，避免免费应用常见的商业化摩擦：

- ❌ 账号/登录/云同步
- ❌ 排行榜、联赛、好友、社交成就
- ❌ 体力/生命值系统
- ❌ 内购、宝石购买、付费道具、皮肤装扮
- ❌ 连签修复、周末护符
- ❌ 推送通知（仅保留本地提醒）
- ❌ 语音识别/口语评分（TTS 替代）

### 8.2 这一取舍的产品意义

- **优势**：体验纯粹、无付费压力、用户留存不依赖 FOMO 机制；适合教育公益、家长放心、隐私敏感用户。
- **劣势**：缺少社交激励、无订阅变现、无法跨设备同步进度、对“成就驱动型”用户吸引力可能不足。

### 8.3 当前商业化可能性

由于代码层面没有内购、广告、订阅，当前产品形态更接近**开源/公益教育工具**或**内容分发框架**。若未来商业化，需新增：

- 云同步与账号体系；
- 付费课程包 / 订阅；
- 家庭/教师账户与进度管理；
- 或者保持免费，通过课程授权/内容合作变现。

---

## 9. 工程与产品质量亮点

| 亮点 | 产品影响 |
|------|----------|
| **无广告/无内购的本地优先架构** | 用户无需网络、无需账号即可学习。 |
| **内容-代码分离** | 运营/教研团队可独立生产课程，缩短内容迭代周期。 |
| **题型与渲染器解耦** | 新增题型无需改核心流程，降低创新成本。 |
| **课程树懒加载与虚拟化** | 即使未来章节多、课程多，列表也能保持流畅。 |
| **主题/深色模式** | [VarnamalaTheme](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/theme.dart) 提供完整语义颜色，符合无障碍与夜间使用。 |
| **可访问性** | 图标按钮 tooltip、MCQ 语义标签、输入标签、对比度适配。 |
| **测试与发布流水线** | 380+ Flutter 测试、Python 工具测试、集成测试、golden 测试、一键打包。 |
| **ADR 文档化** | 20 个架构决策记录，降低团队交接与长期维护成本。 |

---

## 10. 关键文件索引（便于后续查阅）

| 关注点 | 关键文件 |
|--------|----------|
| 入口与启动 | [main.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/main.dart)、[app.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/app.dart) |
| 路由与守卫 | [routing.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/routing/routing.dart)、[course_ready_guard.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/routing/course_ready_guard.dart) |
| 状态/依赖注入 | [injection.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/di/injection.dart)、[providers.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/providers.dart) |
| 主界面 | [home_page.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/home/home_page.dart) |
| 课程树 | [course_tree.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/courses/course_tree.dart) |
| 学习页 | [new_lesson_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/lesson/new_lesson_screen.dart)、[lesson_viewmodel.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/lesson_viewmodel.dart) |
| 题型模型 | [interaction.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/domain/course/interaction.dart) |
| Play Hub | [play_hub_screen.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/play/play_hub_screen.dart) |
| SRS | [srs_provider.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/srs_provider.dart)、[srs_queue_provider.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/srs_queue_provider.dart) |
| 错题 | [mistake_provider.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/mistake_provider.dart) |
| 弱词 | [weak_word_quiz_assembler.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/weak_word_quiz_assembler.dart) |
| 统计 | [study_stats_provider.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/study_stats_provider.dart)、[learning_stats.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/profile/widgets/learning_stats.dart) |
| 成就/游戏 | [game_provider.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/game_provider.dart)、[achievements_provider.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/achievements_provider.dart) |
| 数据仓库 | [course_repository.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/data/course_repository.dart)、[study_log_repository.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/data/study_log_repository.dart) |
| 音频 | [audio_controller.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/application/audio_controller.dart) |
| 设置 | [settings_page.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/settings/settings_page.dart) |
| 主题 | [theme.dart](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/lib/views/theme.dart) |

---

## 11. 风险与改进建议（产品视角）

### 11.1 当前风险

| 风险 | 说明 |
|------|------|
| **TTS 依赖系统语音包** | 土耳其语语音包未安装时， splash 会引导用户安装，过程可能劝退部分用户。 |
| **无跨设备同步** | 换机/重装后进度丢失，影响长期用户留存。 |
| **内容生产门槛** | 课程 JSON 结构复杂，非技术教研人员需要工具辅助。 |
| **内容升级重置进度** | 虽然提供了保留进度选项，但频繁更新可能让用户困惑。 |
| **成就/宝石消耗场景有限** | 宝石目前只有获取，没有使用场景，激励闭环不完整。 |

### 11.2 改进方向（优先级建议）

1. **课程作者工具**：提供 GUI 或 VS Code 插件，降低内容生产成本。当前已有 [docs/authoring/](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/docs/authoring/) 文档，但缺少图形化工具。
2. **离线语音包可选下载**：若目标市场网络条件不稳定，可考虑未来重新引入离线 TTS 模型（需新的 ADR）。
3. **数据导出/导入**：满足用户对进度备份、跨设备迁移的需求。
4. **课程市场/多语言入口**：利用现有的多语言框架，增加语言选择页，展示“更多课程即将到来”。
5. **宝石使用场景**：可兑换头像框、主题色、学习统计卡片背景等纯装饰性奖励，保持无付费压力。
6. **教师/班级模式**：利用已有的学习统计与错题数据，提供教师端查看学生进度（离线导出报告）。

---

## 12. 结论

Varnamala 已经构建了一个**成熟、可扩展、测试充分、产品边界清晰**的语言学习框架。它在“类 Duolingo 体验”与“去商业化、离线、隐私优先”之间做出了明确取舍，适合作为：

- 面向特定语言（如土耳其语）的教育公益应用；
- 内容驱动型语言课程的分发平台；
- 后续引入账号/云同步/订阅后的商业化产品基础。

当前框架层面的主要工作已基本完成（参见 [ADR 0018](file:///c:/Users/DsDogs/Desktop/developper/verna/languageapp/Varnamalaplus/docs/decisions/0018-future4-completion-and-content-handoff.md)），后续最大的产品工作将从**工程框架建设**转向**课程内容生产、用户增长与变现模式设计**。

---

*文档生成时间：2026-07-13*  
*分析范围：代码框架与产品体验，不包含课程具体内容填充度评估。*
