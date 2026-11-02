# P0 逐页旧版结构（设计翻新 · 全 App 重设计）

> 「湿地雾光」全 App 重设计计划的 P0 交付物之一。逐页记录**当前版本**的首屏模块顺序、交互区与状态覆盖，作为新版线框的对照基线；页面清单与处置分类见 [p0-coverage.md](./p0-coverage.md)。源码引用一律用文件与符号名（源码会被改写，不锚行号）。
>
> 上一轮组件级收口留下的主路径截图（浅色/深色/200% 字号/高对比、课程树与课时全流程）在 `dist/design-refresh/screenshots/`，可直接作为本表的图像佐证；本表补足其未覆盖的页面与状态。

## R01–R03 启动、外壳与课程主线

### SplashPage（splash_page.dart）

- 入口：initial 路由；课程壳加载完成即 `replaceAll([HomeRoute])`，`CourseReadyGuard` 反向兜底。
- 平台条件：TTS 可用性提示在鸿蒙走只读说明对话框（无商店/引擎入口），非鸿蒙走三按钮 Google TTS 引导；Web 跳过。
- 主任务：启动闸门（注释明确「不是欢迎页」），boot 失败给重试。
- 旧版结构：`TurnaPageContent(maxWidth: 420)` 居中——失败态为 `PracticeEmptyState`（cloud_off + 重试）；正常态为 Column：`TurnaGeometry` 旅程几何框（内嵌 80 logo）→ `CircularProgressIndicator` → 阶段文案（校验/播种中）。
- 交互区：唯一交互是失败态「重试」；正常态零交互、无人工延迟。
- 状态覆盖：加载（spinner + 阶段文案）、失败（图标 + 重试）齐备；无受限态。

### HomePage 外壳（home_page.dart）

- 旧版结构：`AnimatedContainer`（Tab 0 用 scaffoldBg、其余 surfaceColor）→ `Scaffold`（透明底、每 Tab 独立 AppBar、`extendBody`）→ 内容更新 banner（`Material` + `ListTile`，保留进度/重置/关闭三动作，青绿 12% 淡底）→ `NotificationListener` → `TurnaPageContent(maxWidth: 960)` → `TabStack`（Offstage + TickerMode + ExcludeSemantics 保活栈，未访问 Tab 懒挂载）。
- 底栏形态：64px 悬浮磨砂胶囊（BackdropFilter + 渐变高光），4 按钮（学习 school / 练习 extension / 个人 person / 设置 settings），选中表达为滑动「lens」药丸 + filled 图标 + 11px 加粗标签；滚动隐藏策略为下滑 64px 隐藏、上滑 24px 复现、切 Tab 强制复现。
- 交互区：主导航 = 底部胶囊（经 `TabRouter` 单写路径 + 轻触感）；次交互 = banner 三动作。
- 状态覆盖：外壳自身无 loading/empty/error（交给各 Tab）；会话弹窗顺序硬编码在 `initSession`：游戏字段/宝石/装饰初始化 → 断签检查 → TTS 提示 →（预算未占用且断签）StreakBrokenDialog → Official due 同步 → 内容更新检查。重置确认 AlertDialog（含「先导出」第三按钮）内嵌本文件。
- 备注：`SettingsAppBar` 是 preferredSize 为 0 的占位 stub，设置 Tab 真 AppBar 由内层 Scaffold 自持——「每 Tab 一个 AppBar」的统一假设在设置 Tab 上已破。

### StatAppBar（home/components/stat_app_bar.dart，学习 Tab 顶栏）

- 旧版结构：AppBar(toolbarHeight 60) → leading `CourseSwitchButton`（裸地球 IconButton 进课程管理）→ title 横向 `SingleChildScrollView` + Row：`ScoreCard`（分数计数动画）→ `Streak`（火焰连签）→ `GemsDisplay`（宝石）→ `DueChip`（待复习总数，零值或 Official 不可用时自我隐藏）。
- 交互区：leading 进课程管理；DueChip 点按切到练习 Tab；分数/连签/宝石纯展示。
- 状态覆盖：分数/连签 waiting 用 `Loader`、error 显破折号；DueChip 零值隐藏；title 溢出靠横滚兜底、无视觉提示。
- 备注：DueChip 聚合 5 个数据源（SRS/表达式/语法/错题 + Anki 域）。

### CourseTree（courses/course_tree.dart，学习 Tab 主页）

- 主任务：课程主线浏览：吸顶章节头 + 单元手风琴 + 课时旅程列表。
- 旧版结构：`AmbientBackdrop`（L0 渐变画布）→ CustomScrollView（PageStorageKey）：① official 树不可用警告 banner；② `SliverPersistentHeader` 吸顶 `SectionSwitcher`（100px ↔ 56px 滚动收缩：图标块 + 章节名 + CEFR 标签 + 展开箭头 + 底缘 2.5px 进度条）；③ 单元行序列：`UnitCard` 头（40px 进度环 + 单元名 + 描述一行 + x/y + AttentionChip + 旋转 chevron，展开时与下方课程行拼成一张整卡）→ 展开后的课程行（`LessonRowShell` 行壳 + 24px `ProgressSpine` 旅程线 + 三种瓦片：平面课 `LessonTile` / 多子课 `SubLessonGroupHeader` 组头 / `SubLessonTile` 子课瓦片；next-up 行白底青绿描边浮起 + 「下一课」chip；帘式交错揭示动画）。
- 交互区：主操作 = 点课时/子课瓦片进 `NewLessonRoute`（子课带独立会话，ADR 0064）；次操作 = 点章节头开 `SectionBottomSheet`、点单元头单开手风琴。
- 状态覆盖：课程级失败（错误卡 + 重试）、section loading/error、单元空（去课程管理）、official 不可用 banner——覆盖完整。
- 共享组件：无跨域组件（全部课程域私有族 + TurnaTheme 装饰）。

### SectionBottomSheet（courses/components/section_bottom_sheet.dart）

- 旧版结构：不透明圆角容器（上限 75% 屏高）→ drag handle → 标题「选择章节」+ 数量副标题 + 关闭 → Divider → 分节 tile 列表（44px 图标块 + 名称 + CEFR + 描述一行 + 选中 check / 未选 chevron，选中态青绿描边 + 淡底）。
- 状态覆盖：无空/错态（sections 为空时只剩标题区）。
- 备注：与 SectionPickerPage 功能完全重复（后者无生产入口）；数量副标题由进度字符串拆词拼出，实现脆弱。

### SectionPickerPage（courses/section_picker_page.dart）

- **无生产入口**（路由注册但无 push）。96px 定高章节卡全页列表；无任何 loading/空/失败覆盖。ADR 0062 注释保留。

### CourseManagementPage（courses/course_management_page.dart）

- 旧版结构：AppBar（返回 + 居中标题 + 右上 healing 图标进修复中心）→ busy 线性进度 → 「我的课程」小节 → `ReorderableListView` 课程卡（图标块 + 名称 + 当前/默认徽章 + 卡数副标题 + 可选许可署名 + 激活 check + 溢出菜单 + 拖拽把手）→ Divider → SafeArea 底部添加区（横滚防溢出）：「添加课程」→ `OfficialPendingImportBanner` → 两张虚线添加卡（从 Anki 导入 / 导入 .turnapack）→ 可恢复语言行。
- 交互区：点卡切换课程并返回；卡上菜单（每课 TTS 设置 / 适配方案恢复[仅官方源] / 删除[内置最后一门不可删]）；拖拽排序；底部添加卡；pack 导入 = 文件选择 + 三阶段进度对话框 + 替换确认 + 错误对话框。
- 状态覆盖：busy 全局禁用；切换失败 SnackBar；导入进度/取消/错误；无列表空态（必有内置兜底）。
- 备注：删除序列依赖账本 COMMIT 语义；底部添加区与列表争高度是注释记载的已知坑。

### StreakBrokenDialog 与内容更新（home/streak_broken_dialog.dart、content_update/）

- StreakBrokenDialog：`AlertDialog`——offFire 插图 → 文案 → （有券时）补偿说明 → 动作行（用补偿券[余额 0 禁用] / 知道了）。
- 内容更新现行形态是 HomePage 内嵌 banner + 自建三按钮确认框；`ContentUpdateDialog` 是无调用方的死组件，与内联实现双轨。

## R04–R06 课时、题型与完成

### NewLessonPage（lesson/new_lesson_screen.dart）

- 主任务：一次渲染一题，`LessonViewModel` 驱动提交/推进/完成；`enterStudyScope` 拿备份互斥锁。
- 旧版结构：① `_LessonAppBar`——关闭按钮 + 居中两行标题（课名 + 「小课 k/n · 第 x/y 题」）+ 条件 AI 提示灯泡；bottom 是 6px 圆角整课进度条。② `PracticeSessionBody`——`LessonStageBanner` 阶段名细条（accent 淡底 + 圆点）→ 可选 header（阅读课是折叠 4 行的阅读卡）→ `Expanded` 滚动区（单题 220ms 淡入上移）内嵌当前 renderer → 固定底部操作栏（提交前「核对」，提交后「继续/知道了」，autoAdvance 题型整条不出现）。
- 阶段切换仅表现为阶段条文本与 AppBar 进度/题号变化，无页面级转场；换题回滚顶部。
- 交互区：退出 = 左上 X（未完成弹确认，完成直接 pop）；提交与推进共用底栏按钮；无跳过。
- 状态覆盖：加载失败（图标 + 重试）、加载中 spinner、空内容占位、退出确认、小课检查点/完成庆祝/掌握重试三弹层；键盘无页面级保障，靠 Scaffold 默认缩放 + 各文本 renderer 自行 autofocus/unfocus。
- 共享组件：renderer 注入集合 + `lookupRenderer` 分发；`PracticeSessionBody`、`LessonPracticeCard`、`AiHintSheet`。

### 题型 renderer 清单（lesson/components/interactions/，17 题型 + 1 基类）

| renderer | 题型 | 旧版作答版面 |
|---|---|---|
| interaction_renderer.dart | 基类/分发器 | 定义 `InteractionRenderer`、sealed-switch 分发、`LessonActionDraft` CTA 契约；共用件：`InteractionBody`（统一内边距外壳）、`InteractionOptionTile`（玻璃卡选项 + 判定抖动/弹跳 + 圆形勾叉标）、`WordChip`、`LessonCheckButton`（渐变主 CTA）、`LessonCorrectAnswerBanner`（答错绿条）、`SpeakerButton`、`BinaryGradeRow`、`SectionCaption` |
| multiple_choice_renderer | 单选 | `SectionCaption` + 大号题面（可选题图/媒体条）→ 纵向全宽选项 tile；提交后正确项绿、误选红抖动，答错尾部追正确答案横幅 |
| multi_select_renderer | 多选 | 同单选 + 「已选 x/需选 n」计数行；无正确答案横幅 |
| fill_blank_renderer | 填空/选择填空 | 句子 `RichText` 居中、空格内联描边输入框（或占位块）；选择填空下方 `Wrap` 词块；提示语黄色灯泡 chip |
| translate_sentence_renderer | 翻译造句 | 源句 `LessonPracticeCard` 卡 → 1-3 行多行输入；提示词是可点 `ActionChip` 追加进输入框 |
| listen_and_pick_renderer | 听音选图/词 | 顶部大圆喇叭（进题自动 TTS）→ prompt → 选项 tile 列 |
| type_the_word_renderer | 听写打字 | 大喇叭 + 居中 prompt + 居中大号单行输入框（回车提交） |
| listen_only_renderer | 听力小结 | 纯呈现卡：prompt + 大喇叭 + 播放后才揭示的浅青底 transcript；卡内自画提交按钮（不进底栏） |
| show_word_renderer | 生词展示卡 | 整张卡即点击目标（tap 提交自动推进）；词条可点读 + 词性 + 图 + 释义 + 例句浅底块 + 「点按以继续」；canonical 链接改渲染官方卡视图 |
| anki_card_renderer | 翻面卡 | 大卡居中，点卡缩放脉冲翻面；正面词条 + 媒体条，翻面答案 + 媒体；卡下固定 88px 区先「显示答案」后换双按钮自评 |
| image_recall_renderer | 看图回忆 | 图即题面；「显示答案」后浮出大号答案文本 + `BinaryGradeRow` 自评；无对错染色 |
| dictation_renderer | 听写（无题面） | 刻意不渲染文字题面：caption + 媒体条 + 居中大号输入框 |
| reorder_sentence_renderer | 拼句排序 | 可选中文题面卡 → 描边答案槽区（点击退回、长按拖动）→ Divider → 词库区（点词飞入 + Overlay 幽灵芯片动画）；提交后槽区整框染色 |
| reading_mcq_renderer | 阅读选择 | 原文由页面级折叠卡承担，本区只有题面 + 选项列；答题需经「展开原文」全屏 sheet |
| reading_true_false_renderer | 阅读判断 | 陈述句浅色容器 → 一行两个等宽对/错 tile |
| reading_short_answer_renderer | 阅读简答 | 题面 + 单行输入框 |
| read_aloud_renderer | 跟读 | prompt + 目标句（提交后逐词染色 Wrap）+ 示范喇叭 + 圆形麦克风（录音中变红显 partial 转写）；不可用时整卡退化听音体（ADR 0061） |
| anki_html_card_retired_renderer | 已退役占位 | 图标 + 「此类卡已退役」+ 卡内继续按钮，兜底不抛异常 |

### 完成体验（lesson/components/lesson_dialogs.dart）

- 课时完成弹层（`showLessonCompletionDialog`）：延迟 300ms 弹出、不可点外关闭——随机庆祝徽章头图（全对叠星标）+ 随机标题/副标题三套文案抽签 → 大号正确率圆环（按阈值绿/黄/红）→ 2×2 统计格（对/错/用时/XP）→ 成就横幅 → 可选脚注 → 可选逐题对错列表（错题附正确答案）→ 底部双出口：全宽渐变「继续」+ 弱化「返回课程」（**两按钮回调一致，均仅关闭**）；关闭后无条件 pop 课时页。
- 小课检查点：图标 + 标题 + 小课名 + 对错两格 + 「继续下一小课」/「休息一下」。
- 掌握度重试：标题 + 说明 + 重试/结束。
- 三弹层各写一套主按钮（Ink 渐变 / ElevatedButton 定高 48），未与 `LessonCheckButton` 统一。

### 其余课时组件

- `practice_session_body.dart`：阶段条 + header + 滚动题区 + 固定底栏总装，720px 最大宽。
- `lesson_stage_widgets.dart`：阶段名细条、折叠 4 行阅读卡、0.7 高 `DraggableScrollableSheet` 全屏阅读。
- `ai_hint_sheet.dart` / `ai_depth_tutor_sheet.dart`：讲解底部 sheet（流式回复限高 360）与二级深度讲解 sheet（三 genre 单选 + 一次性结构化结果）。
- `anki_media_strip.dart`：每条音频一个喇叭、每图 160px 缩略，解析失败静默降级。
- `lesson_practice_card.dart`：练习域主卡容器（front/back/surface 三变体，ADR 0062）。

### R04–R06 共性问题

1. **主 CTA 位置三套并存**：核对型交页面底栏；揭示/自评型（翻面卡、看图回忆、听力小结、跟读降级、退役占位）在滚动内容里自画按钮；生词展示卡整卡点击——同一节课主操作位置随题型跳动。听力小结/退役占位提交后还残留禁用按钮，与底栏「继续」双按钮同屏。
2. **正误反馈无统一区域**：全部题型共用「选项染色 + 答错才出现的横幅」两件套，答对无文案层反馈；横幅插在滚动内容尾部，长题需滚动才能看到正确答案。
3. **题型视觉同质化**：MCQ 族题面与选项裸排画布，题型区分只靠一行全大写 caption，统一内边距一栏到底。
4. **阶段与进度表达薄弱**：仅一条细色带 + AppBar 6px 进度条和文字题号，无阶段分段可视化。
5. **键盘处理散落**：无页面级 scroll-into-view；5 个文本题型各自 autofocus/unfocus。
6. **完成弹层信息过载、出口语义重复**：85% 屏高内堆徽章 + 圆环 + 统计 + 成就 + 明细，双出口行为完全一致。

## R07–R10 练习、复习与洞察

### PlayHubScreen（play/play_hub_screen.dart，练习 Tab）

- 旧版结构（CustomScrollView）：① 顶部留白；② `TodayHeroCard` 主 CTA——teal→sky 渐变大卡（标题 + 下一队列副标题 + 右侧大数字 + 四队列 chips 速览）；③ Anki 同步失败重试条（条件）；④ 「复习队列」`AdaptiveCardGrid` 2×2（错题/单词/语法/智能练习 或 Anki 变体，各带计数 badge）；⑤ 「练习工具」三列 `CompactToolTile`（弱词/词典/复习进度）；⑥ 底部安全距离。
- 交互区：短按直接导航；**长按弹 `PlayInfoPopup` 数据浮窗**（Hero、队列格、弱词、进度、智能练习均有；词典无）。
- 状态覆盖：Anki due 不可用重试条 + badge 破折号；AI 未配置警示色 badge；生成中 badge 省略号；无全局 loading/空态兜底。
- 平台条件：智能练习 tile 鸿蒙不渲染（ADR 0056）；Anki 课裁剪单词/语法/词典/弱词入口。

### DailyChallengePage / WeakWordsPage / MistakeReviewPage（三个同构会话壳）

- 三页是同一模式的三份复制：AppBar（标题 + 题号副标题 + 底部 4px 彩色进度条，各自 accent 色）→ 备份阻断 `PracticeEmptyState` / 空态 / `PracticeSessionBody` 渲染当前题 → 完成弹课时完成弹层。仅装配器与 accent 色不同。
- `DailyChallengeRoute` 无生产入口（设置页仍保留其 Anki 出题开关）；三页均无失败态、退出无确认（错题复习未做完直接放弃无提示）。

### UnifiedReviewPage（review/unified_review_page.dart）

- 主任务：全卡源共用的翻卡-二元评分会话；`SrsReviewPage` 以 widget 嵌入（路由本身无 push）。
- 旧版结构（三态整页切换）：空 → `PracticeEmptyState`；完成 → `UnifiedReviewCompletion`（徽章 + 三格统计玻璃卡 + XP/宝石 + 成就横幅 + 撤销末卡 + 「完成」/「再来一批」）；进行中 → `ReviewProgressHeader`（关闭 + teal 进度条 + x/n + AI 讲解[鸿蒙隐藏] + 撤销）→ 响应式边距 → `StudyCardSurface` 主卡 → 错误/重试行 → 底部动作区（未揭示 = 52 高「显示答案」实色按钮；已揭示 = `BinaryRecallBar` 记得/不记得带间隔预览；结构化题 = renderer 直接作答）。
- 状态覆盖：空、完成、写失败重试、预览失败重试、副作用警告、提交禁用；无整体 loading（items 调用方同步备好）。

### SrsReviewPage / GrammarReviewPage

- SrsReview 是纯薄壳：items null 时 spinner，否则整页交给 `UnifiedReviewPage`。
- GrammarReview 自成状态机（唯一不走 Unified 的会话）：空队列（区分「有到期但加载异常」文案）→ 完成 → 进行中：AppBar（标题 + undo + x/n）→ 主体按相位切换——`_GrammarCard` 语法卡（tap 翻面，teal 玻璃，解释 + 出处课名）或 `_PracticePanel`（玻璃容器内嵌 renderer）→ 底部按相位：显示解释 / 下一题 / `ReviewRatingBar`（不认识/认识带间隔预览）。
- 状态覆盖：评级失败仅记日志无 UI 提示；undo 有。

### 错题四页

- MistakeListPage：AppBar（标题 + 洞察 icon）→ 空 / `RefreshIndicator` + CustomScrollView：三格统计头（flatPaper）→ 筛选 chips（全部/单词/语法带计数）→ 错题卡列表（`_MistakeCard`：44px 类型圆 icon + 题面 + 语法 chip + meta 行[相对时间 + 重写进度点] + 右上「练习」按钮 → 你的答案 vs 正确答案双底色块 → 可选词典释义行 → 底部「复习语法」/「掌握了」文字按钮）。
- MistakeDashboardPage：全空 / ListView 五卡：三 KPI 行 → 14 天自绘柱状图 + 文本摘要 → 堆叠比例条 + 图例 → 重复 ≥2 次 Top5 → 最久未攻克 Top3。仅下拉刷新，卡片全部不可点。
- MistakePracticePage：单题重做，约 120 行最小页面（renderer + 继续按钮 + 「无法练习」文案）。
- MistakeReviewPage 见上节同构会话壳。
- 状态覆盖：错题族仅空态无失败态；与复习进度页的 7 日柱状图是同一自绘模式的两份拷贝。

### ReviewProgressPage / LearningInsightsPage / ReviewSourceDetailPage

- ReviewProgress（今日仪表盘，本族状态覆盖最全）：错误无缓存 `_ErrorState`（重试）/ 无快照 5 块骨架 / 刷新失败保留旧数据 + 内联错误横幅 → `_TodayHero`（日期 + 今日目标大字 + 进度条 + 继续复习按钮；大字号纵向堆叠）→ 三卡（待复习/新卡/逾期）→ 连胜卡（火焰 + 保护券 chip + 7 日柱状图 + 摘要）→ 今日质量单行 → 来源前 5 行 → 底部「打开学习洞察」。**`_SourceTile` 带 chevron 但整行不可点（视觉暗示失真）**。
- LearningInsights（重分析页）：筛选面板（来源 chips 横滚 + 类型/到期分段控件）→ 两行六 KPI（无数据显破折号不造假）→ 记忆曲线 fl_chart 折线 + 五档分段 → 活跃热图（Wrap 小方块）→ 学习统计段 → 来源列表（选中态高亮 + chevron 开详情）。**FutureBuilder 无 error 分支——出错停在 spinner**。
- ReviewSourceDetail：可用性 banner（条件）→ 三指标卡 → 趋势摘要纯文本 → 活跃时「开始复习」按钮。**全族唯一未接入 flatPaper/玻璃语言的页面（裸 Material Card），视觉与母页割裂**；无空态。

### R07–R10 共性问题

1. **三套会话外壳并存**：UnifiedReview、Grammar 自研状态机、LessonViewModel 会话壳三份复制——进度条样式、评分条（BinaryRecallBar vs ReviewRatingBar）、完成体验互不相同。
2. **完成页三轨制**：UnifiedReviewCompletion（玻璃卡）、ReviewCompletionState（Center 纯文本，显旧）、课时完成弹层——同一「复习完成」语义三种视觉。
3. **卡片容器语言不统一**：SoftCard 玻璃皮 / flatPaper / 裸 Material Card / 各自手写 flatPaper 同构容器——「统计卡」至少四种实现。
4. **失败态普遍缺失**：洞察页出错停 spinner；错题两页无失败态；语法评级失败无感知；对照复习进度页的骨架 + stale-while-revalidate，全族未对齐。
5. **孤儿路由**：DailyChallenge、UnifiedReview 注册无 push。
6. **入口冗余与暗示失真**：同一目标多入口；来源行假 chevron。

## R11–R13 词典与记忆卡

### DictionaryPage（dictionary/dictionary_page.dart）

- 旧版结构：AppBar → 搜索框（filled 圆角 + search 前缀）→ 结果区二选一：空态（区分「未搜索」/「无匹配」）或词条 tile 列表（kind 标签 → 词头 → 词性 → 音标 → 3 行截断释义，右侧 AI 富集[鸿蒙隐藏] + 发音按钮）。
- 交互区：250ms 防抖（UI isolate 线性全表扫，与卡牌浏览器同模式各自手写）；发音带失败反馈；AI 按钮开底部 sheet（自动富集/取消/重试/复制/保存）。
- 状态覆盖：两种空态、AI sheet 全态；列表本体同步无加载/失败。

### AnkiImportPage（anki/anki_import_screen.dart，5 步向导壳）

- 旧版结构：AppBar（返回走确认）→ `WizardStepper` 五点连线（大字号有紧凑变体）→ 步骤体：Selecting（大图标 → 中断导入横幅 → 媒体开关 → 错误红字 → 选文件大按钮[有未完成导入时禁用]）/ AlreadyImported（图标 + 打开/替换）/ Parsing（进度 + 取消）/ Committing（进度 + 不可取消提示）/ Previewing（整体委托 `ModernAnkiImportPreview`）/ Completed（委托 `AnkiImportDoneStep`）。
- Previewing 主体：错误横幅 → 预览头卡（文件名 + 牌组数 + 三格统计 + 原型 chips）→ 三模式单选卡（智能练习[推荐]/经典翻卡/官方保真）→ SmartAdaptation 区（**鸿蒙不渲染**；逐 notetype 生成/应用/恢复，AI 失败不阻塞导入）→ blocking 警告（「跳过该类型」/「选择正面」开 sheet）→ 逐 notetype 模式行 → 牌组目录树（`::` 分层、checkbox 含入、原型 chip 开样本 sheet）→ 底部粘性导入栏（阻塞时禁用 + 提示）。
- Completed：成功图标 → 大号卡数 → 分组统计（来源/词汇/媒体/复习规则）→ 学习进度徽章 → 「立即学习」（唯一切课程动作，ADR 0043）/「查看牌组」/「完成」。
- 状态覆盖：解析可取消、提交不可取消、失败叠加在来源态上、冲突、中断横幅——齐备。

### AnkiCardBrowserPage / AnkiDeckStatsPage（anki/）

- Browser：AppBar（标题 + 「复习全部」）→ 搜索框（250ms 防抖）→ 横向过滤 chips（标记/埋藏/暂停 + 熟识度四档品牌色）→ 牌组下拉 + 标签输入（不可用时整行隐藏）→ `Card/ListTile` 列表（旗标 icon + 懒加载逐行预览 + Official/note id 副标题 + 行菜单复习/暂停）。状态覆盖较全（loading/失败重试/不可用/空）。
- DeckStats：总卡数卡 → 卡状态 → 旗标/暂停/埋藏 → 今日答题 → 三列预测 → 保留率 → 按间隔保留曲线（复用 `RetentionCurveChart`）→ 语义说明。**FutureBuilder 无 error 分支（异常即无限转圈）**；纯展示无操作。

### AnkiReviewPage 复习中枢（anki/anki_review_screen.dart）

- 旧版结构：AppBar（标题 + 「导入新牌组」）→ due hero 区三态（不可用警告卡 + 重试 / 渐变 hero[图标 + due 拆解 + 大计数 + 全宽「复习全部」] / 已清空卡）→ 「我的牌组」→ `ReorderableListView` 牌组卡（拖把手 + 图标 + 名称/描述 + due badge[null 显破折号] + 箭头 + 三点菜单；卡下「浏览牌组/牌组统计」文字按钮行）→ 空态（去导入）。
- 备注：legacy 源 due 恒 0（调度器退役，fail-closed）；菜单含置顶/每日上限/卸载（仅 legacy）。

### AnkiReviewSessionPage 正式会话宿主（anki/anki_review_session_page.dart）

- 旧版结构：加载路径（准备面板 / 阻塞面板[重试 + Review All 时「稍后处理」] / fail-closed 错误 / 空队列）；会话路径：完成 → `UnifiedReviewCompletion`（Review All 含失败源红横幅 + 只重试失败源）；进行中——**Android**：`ReviewProgressHeader`（进度 + 撤销）→ `_AnkiSessionToolbar`（来源 chip + 重做/埋藏/暂停）→ `StudyCardSurface` → 底部（blocked 重试 / 写入不安全重试 / 显示答案大按钮 / `BinaryRecallBar`）；**鸿蒙**：只渲染卡面（原生 ability 盖面，AppBar/进度头/工具栏/评分栏全无，chrome 由原生回调供给）。
- 状态覆盖全族最全：loading、error（fail-closed 专门文案）、源级 + 当前卡级 blocked、空队列、Review All 编排、备份互斥。
- 重设计约束：**平台 chrome 契约必须显式化，否则鸿蒙会被画上不可用的按钮**；第三方 HTML 由 WebView/原生渲染，卡内容区不可加包装/阴影/缩放（ADR 0062 例外 + CSP 限制）；JS 硬关保持 fail-closed。

### OfficialAnki 三页（anki_official/）

- MappingPage：**无生产入口**（流程被 quick/mcq sheet 内联取代）。状态条（阻塞红/需注意黄/正常绿）→ 正面二选卡 → 样本预览卡 + 交换按钮 → 题型 ChoiceChip Wrap → 正反面角色下拉 → 折叠更多 → 底部三动作。
- RepairCenterPage：`SettingsScaffold` → catalog 未就绪降级视图 / 主视图：busy 进度 → 健康总览卡（三状态行 + 一键优化/修复）→ 全空提示 → 孤儿文件段 → 未完成导入段 → 待清理段 → 隔离段 → 维护作业段 → 失败作业段 → 高级工具（完整性检查/重建索引/导出诊断）。所有破坏性动作带确认。**doctor 报告异常被静默吞、孤儿扫描失败被当「无孤儿」**。
- ReviewerPage（单卡内部预览）：**DiagnosticsReleaseGuard，release 默认拦回 Home**；booting 圈 / bootError 错误面（无重试按钮）/ 正常卡面舞台（含翻面/重播预览控制）。

### R11–R13 共性问题

1. 搜索/防抖/懒加载三件套在词典与浏览器各写一份。
2. 状态覆盖不齐：DeckStats FutureBuilder 无 error 分支；修复中心吞错；加载指示三种形态并存（圈/线/准备面板）。
3. OHOS/Android 结构分叉深埋页面内部（会话宿主与卡面舞台两处大 build 分叉）。
4. 第三方 HTML 保真硬约束：卡内容区不得包装（材质、阴影、缩放均不可）。
5. 少量硬编码中文字面量绕过 AppStrings（目录树「个章节节点/张卡片」、映射页「（共 N 张）」）。
6. 入口语义分裂：Mapping（无入口）、Reviewer（诊断守卫）、Import/RepairCenter（用户可达）三类可达性并存，清点需分开标注。

## R14 AI

### AiHubPage（ai/ai_hub_page.dart）

- 入口：Play Hub 智能练习 tile（鸿蒙不渲染 tile；**路由无平台 guard，深链可达，页内只查配置完整性**）。
- 旧版结构（CustomScrollView）：① `_HeroSection` 青碧渐变引擎卡（preset/聊天模型/掩码 key；未配置出警示 chip，点击进 API 配置）→ ② 页面级 AI 生成标识横幅 → ③ 「我的练习」预览块（运行中任务横幅 + 最近 3 条 + 任务计数行）→ ④ 「继续」最近 3 条可恢复任务 → ⑤ 生成入口两张工具卡 + 「伴学」2×2 宫格（自由问答/学习诊断/收藏讲解/深度讲解）→ ⑥ 助手偏好卡 → ⑦ 系统提示词工具卡。AppBar 右上帮助进功能指南。
- 状态覆盖：hero 两态、继续空态、练习块三态；无页面级失败/取消提示。

### AiPracticeLibraryPage / AiPracticeRunPage / AiPracticeDetailPage

- Library：AppBar（「选择」）→ 下拉刷新 + 三组列表（收藏/草稿[多一行过期脚注]/生成任务）→ 底部非选择模式「生成练习」大按钮 / 选择模式批量底栏（全选/收藏/删除）。卡片菜单按五态（queued/running/ready/failed/interrupted）条件出项。
- Run：AppBar（关闭 + 双行标题 + 底部进度条）→ `PracticeSessionBody`（与课时同壳，纯内存播放不写课程树）。完成弹窗里「答对 x/y」是硬编码中文。
- Detail：**断链页**——`AiPracticeDetailRoute` 被两处 push 但从未注册，点击「详情」即路由错误。页面本体：头（标题 + 来源/等级/过期 · 主题）→ 质检报告逐条 → 大纲两级缩进 → 生成历史（多版本才显示）→ 底部「开始练习」/「重新生成」。

### 聊天双页（ai_tutor_chat_page.dart / ai_hint_chat_page.dart）

- Tutor：AppBar（会话列表 + 新会话）→ 未配置整页面板 → 模式分段条（roleplay 追加场景 chips 横滑）→ 消息气泡列表（流式目标气泡独听高频 revision）→ 错误横幅 → 细进度条 → 输入行（busy 时发送换停止）→ 免责声明。
- HintChat：围绕某题的追问对话；AppBar 带「收藏本条讲解」；快捷追问 chips；错误优先走横幅、无映射时退私有错误气泡。
- 生命周期不对齐：tutor 的 provider 页面自建自毁，hint 的是全局单例跨页存活；tutor 有会话列表持久化、hint 只有单条保存。

### AiDiagnosisPage / AiSavedListPage / AiApiConfigPage / AiFeatureGuidePage

- Diagnosis：免责声明 → 生成/停止大按钮 → 可选错误横幅 → 报告三节（弱项/建议/练习点子，裸 `ListTile`——全族唯一未卡片化页面）→ 复制/收藏 → 「按难点生成练习」。无报告未生成时的空态。
- SavedList：搜索框 → 空态或玻璃实面卡列表（标题 + 删除 / 3 行摘录 / 来源·时间脚注）→ 详情底部 sheet（可选文本 + AI 标识 + 复制）。
- ApiConfig（约 1300 行）：PopScope 拦截返回先冲草稿 → 状态卡（已配置/未配置 + 掩码 key）→ 凭据安全说明 → 范围说明 → 连接组卡（厂商 2×N 网格 + BaseURL + 兼容提示）→ 模型组卡（key 输入不回显 / 聊天模型 + 快选 / JSON 模型 + 快选 / 推理开关）→ 测试连接 + 保存 + 七类错误归类文案 → 危险区（清除凭据/恢复默认，均确认）。草稿 500ms 防抖 + 双兜底冲存。
- FeatureGuide：hero 卡（同款渐变 + 配置/隐私 chips）→ 「伴学」4 卡 + 「复习」2 卡，每卡固定五段（标题/作用/场景圆点列表/流程编号列表/小贴士着色盒），tap 直达功能。
- 教材导入（TextbookImportPage）：tombstone，仅存「迁移说明」body + 打开 GUI / 复制地址；活入口只剩 Hub 最近任务继续行。

### 全局 AI sheet 与组件

- 生成练习 sheet：模式分段（按学习数据/自定义课程）→ 数据模式表单（来源三选 + 等级 + 调用估算）或自定义表单（主题 + 等级 + 结构下拉 + 模板下拉 + grounded 开关）→ 后台运行提示 → 开始生成（未配置/忙时禁用）。只入队，进度在库。
- 卡片讲解 sheet：免责声明 → 未配置紧凑面板或限高 360 流式卡 → ready 后复制/收藏。
- 系统提示词 sheet：功能 chips（已自定义打陶土点）→ 生效预览（等宽只读）→ 追加编辑器 → 保存/恢复。
- 组件族：`AiGroupCard`/`AiSurfaceCard`/`aiSheetInputDecoration`（族内设计基元）、五态练习卡、任务横幅、错误横幅、未配置面板（整页/紧凑两档）、合规标识三件套（单条角标/页级横幅/复制附加函数——《标识办法》硬要求）。

### R14 共性问题

1. **断链路由**（见 Detail 页）。
2. **四套卡面语言并存**：SoftCard 玻璃卡 / AiGroupCard 旧软彩卡 / 裸 ListTile / 聊天系旧色 AppBar。
3. 未配置与错误呈现三路并行（整页面板 / 纯文案警示盒 / hero chip），错误通道三种（横幅 / 私有错误气泡 / SnackBar）。
4. 状态缺口：诊断无空态、Hub 不呈现失败任务（刻意只在库）、练习运行无退出确认。
5. 平台防护只在入口层：深链可直达全部 AI 页，兜底全压引擎层 dispatch。
6. i18n 漏网：生成 sheet 模板名与错误文案、练习运行「答对 x/y」等硬编码中文；三处输入框用裸 OutlineInputBorder 而非族内基元。

## R15–R18 个人、设置、诊断与说明页

### ProfilePage（profile/profile_screen.dart，个人 Tab）

- 旧版结构（瘦身后的「slim profile」）：① `AccountWidget` 身份 hero（3px clay→sand 品牌条 + 头像 radius 32[点击换头像] + 名字/单行 bio + 右侧编辑/分享两圆钮）；② `TodaySummaryCard` 今日三格（XP 暖徽 / 分钟 / 正确率，竖分隔线）；③ `ProfileQuickActions` 到期 chip 行（非 Anki 课 3 chip / Anki 课单 chip）；④ 一张玻璃入口卡两行（学习统计 → 复习进度、成就 → 成就页[带 unseen 红点]）。
- **宝石/连胜/累计统计刻意外迁**：宝石与连胜在学习 Tab 顶栏，累计统计在复习进度页——个人页首屏 4 块不含它们。
- 状态覆盖：几乎无 loading/失败态（本地同步读）。
- 分享：`_ShareProgressSheet`——预览即捕获目标（360×600 品牌海报：渐变标题 + 吉祥物叠统计卡 + 引言），强制 lightTheme 常量色板自包含。

### AchievementsPage 与头像环

- Achievements：clay 渐变 hero（x/y 大数字 + 进度条 + 完成率）→ 「距离最近」1-2 张推荐卡（零进度不占位）→ 三筛选 chip → 2 列徽章网格（locked/inProgress/unlocked/maxed 四态 + NEW 角标）→ 「全部」筛选时最近解锁列表。进入快照 unseen、退出 markSeen。详情是 `DraggableScrollableSheet`：徽章头 + 「下一步还差 x」提示条 + 层级阶梯逐行（勾/锁圆钮 + 稀有度/目标/宝石/日期）。无加载骨架、无失败态。
- AvatarRingsPage（在 settings 目录、个人域内容）：三 Tab（头像环/个人主题/完成特效）→ 宝石余额卡 → 连胜券卡（余额/月购/上限 + 购买按钮）→ 各 Tab 目录列表（单卡 divider 分隔 tile：预览 + 名称/价格 + 使用中 chip 或兑换按钮）。购买三结果态；高对比与 1.5 倍字重有纵排适配。

### SettingsPage 落地页（settings/settings_page.dart，设置 Tab）

- 旧版结构（内层自持 Scaffold AppBar，外壳槽位是零高 stub）：① 品牌渐变个人摘要卡（头像 + 名字 + 目标摘要，tap 进账户）；② 「快捷」2×2 格（语言/主题/提醒时间/字号，宽屏 4 列、大字号退 1 列）；③ 「学习」分组卡（学习/外观声音/无障碍三 tile）；④ 「数据与系统」分组卡（数据备份/高级两 tile）；⑤ 关于卡（单 tile + FutureBuilder 版本号）。maxWidth 720 居中。
- **不是「每个开关一张卡」**：落地页无开关，是分组导航；分类页是「一卡多行 + divider」。

### 八个分类页（settings/pages/）

- Account：装饰品入口单卡 + 「目标」卡 3 条滑块（XP 档位/学习分钟/课时）。身份编辑留在资料 hero（注释明确分工）。
- Learning：**一张大卡 10+ tile**（语言选择 PopupMenu / 课程更新 / 课程恢复 / TTS 开关[鸿蒙副标题分支] / 条件 TTS 语速 / 条件跟读开关[鸿蒙隐藏] / FSRS 保留率 / 复习批量 / 每日提醒[鸿蒙无通知注册时禁用并解释] / 连胜券自动使用）→ 「Anki」卡（新卡/复习上限 + 每日挑战纳入开关）→ 恢复默认单行卡。
- AppearanceSound：外观分段选择 + 自动旋转开关卡；音频一张卡（音效/触感/TTS 引擎 tile 三态副标题）。这是最接近「每开关一卡」的一页。
- Accessibility：一张卡 6 tile（全局字号/卡片字号/减弱动效/高对比/感官削弱/专注模式），拖动实时预览。
- DataBackup：「数据」卡 4 动作（导出 sheet / JSON 导入 / 远程备份[鸿蒙隐藏] / 迁移 zip）→ 「学习记录」卡（清空错题本）→ 「危险区」卡（重置进度/注销账户，注销三选含「先导出」）。
- Advanced：引言 + 一张卡 4 导航 tile（AI 连接[鸿蒙隐藏] / 存储与性能 / 系统健康与诊断 / 旧版与兼容性）；Legacy 二级页 = 强制禁 JS 开关 + 条件实验性卡（AI 缓存/strict-schema/用量只读）+ 恢复默认。**文件尾注提及的 developer lab 路由已不存在（注释过期）**。
- About：单卡 4 行（关于/隐私/开源许可/版本 footer）。

### 诊断与备份四页（R17）

- SystemHealth：条件双 banner（数据完整性 danger / 未确认告警）→ 大图标等级卡 → 主要问题列表或「一切正常」→ 操作卡 8 tile（自检/确认告警/就诊建议/导出报告/复制摘要/安全模式/原始日志/清空日志）。
- StorageDiagnostics：顶部细进度 → 总量卡（大数字 + 自绘静态环形图）→ 全宽清缓存 → 全宽优化数据库 → 修复中心文字链接 → 2×2 类别格（学习数据/媒体/官方合集/缓存，后两者下钻）→ 条件孤儿警告卡 → 内存卡 → 扫描时间脚注。**卡片自绘硬编码字号，脱离 SettingsCard 体系**；状态覆盖全族最完整（loading 保留旧数据/错误重试/孤儿/按钮 busy）。
- StorageCategoryItemsPage：**非路由**（手工 push + bool 返回协议）——顶部进度 + 总字节 → `CheckboxListTile` 多选列表 → 底部红色「删除所选」+ 条件「强制清空幽灵文件」。
- TransparencyLog：清空按钮 → teal 导语 hero → 最近操作日志卡（50 条）→ 错误日志卡（50 条）→ 一般数据卡（版本/平台/OS/屏幕/语言/时区）→ 脚注（JSONL 路径 + 复制）。整页套课程树渐变背景。
- RemoteBackup：条件 blocked 卡 → 服务器卡（三字段 + 保存并测试 + 结果行）→ 备份卡（含媒体开关 + 上次时间 + 立即备份 + 阶段进度行）→ 恢复卡（远端 manifest 状态副标题）→ 中性提示卡。密码只进安全存储不回显；鸿蒙页内兜底卡「平台不支持」。
- 课程更新 tile：URL 输入对话框承载六阶段状态（checking/feed/downloading/validating/installing/applying），下载失败与应用失败分开重试。

### 说明三页与全局反馈（R18）

- AboutTurna：双 Tab——「关于」= hero 卡（品牌条 + 图标 + 名称 + tagline + 版本 chip + 三事实 Wrap）→ 「这是什么」段 → 「亮点」卡 → 「链接」卡 5 行（未配置外链渲染禁用 + 原因）→ 隐私入口 → 致谢 → 版权；Tab 2 直接内嵌 `ChangelogFromAsset`。
- PrivacyDetails：hero（含「最后更新」角标）→ 7 节长文（概述/不收集什么/数据存储/网络访问双栏 callout[非 AI 深绿离线 / AI 深蓝按平台]/外部链接/你的权利/政策更新/联系方式）→ 滚动超 80px 后右下单向滑入「透明度日志」pill。
- ChangelogPage（路由无生产 push，主入口是关于页 Tab 内嵌）：引言 → 时间线概览卡（7+ 步圆点连线）→ 条件 fallback 警示条 → 每版卡片（最新版 teal 强调）→ 一键复制 → 脚注。
- 全局弹层见覆盖表；弹层标题/正文/关闭/操作关系目前全部沿用 Material 默认，未按品牌重画。

### R15–R18 共性问题

1. **「说明页三胞胎」私有组件重复**：关于/隐私/透明日志各自维护结构相同的 `_AboutCard`/`_SectionHeader` 副本（更新日志是第四份），无法统一改版。
2. **存储双页脱离设置域组件体系**：自绘 Container + 硬编码字号 + 主题 cardColor；StorageCategoryItems 游离于路由表外。
3. **状态覆盖两档分化**：诊断/备份/课程更新一档齐全；资料/成就一档几乎无 loading/失败。
4. **玻璃档位口径跨域不一致**：ADR 0063 的「落地页 subtle / 深层页 quiet」靠 SettingsCard 默认值约定，个人域仍用旧档、成就详情用旧式描边。
5. **平台条件入口三种形态并存**：tile 整体隐藏（AI/跟读/远程备份）、tile 禁用并解释（提醒）、页内兜底卡（远程备份直开）——需统一「隐藏 vs 禁用 + 原因」决策规则。
6. **过期注释与死入口**：developer lab 尾注、ChangelogRoute。
