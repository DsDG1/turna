# ADR 0054 — AI 练习：统一 section JSON、后台生成队列、AI Hub 练习库

> **Status**: Accepted ｜ **Date**: 2026-10-21
>
> 关联：[ADR 0032](./0032-about-page-tool-gui-content.md)（tool/gui 不进 app 本体）、[ADR 0053](./0053-turnapack-external-courses.md)（课程 JSON 契约只有一份）

## 决策

### 1. 移出课时内 AI 编辑

- 删除课时 AppBar 的「AI 课程助手」入口、`AiLessonHelperSheet`、`AiLessonHelperProvider`、`AiLessonUndoStore` 与撤销横幅。
- 「降低/提高难度、加 3 个练习、改听力、优化提示词」这组针对单节课的快捷 chip 一并删除。
- 单题 AI 提示（`AiHintSheet`）与深度讲解（`AiDepthTutorSheet`）保留：它们解释当前题，不改写课程。
- 「让 AI 改一版」的能力只保留在**生成物**上：对「我的练习」里的一条草稿做整节自由文本调整，不再触达内置课时。

### 2. 生成物只认一份 JSON

- 唯一格式是 [`docs/authoring/course-layout.md`](../authoring/course-layout.md) 的 section 契约：`section → units → lessons → content`。
- **练习** = 1 unit × 1 lesson（`review`；模板契约允许 review 使用 `stages`）；**自定义课程** = N units × M lessons。两者共用同一 schema、同一校验器、同一套提示词。
- 提示词语义对齐 `tool/gui/src/backend/ai/{prompts.py,ai_phased.py,ai_pedagogy.py,config.py}`：
  - 大纲阶段只出 `id/name/words/expressions/grammarPoints/units[].lessons[].template/targetWordIds`；
  - 逐课阶段填充 content，id/template 以大纲为准；
  - 校验失败带错误列表重问一次；
  - 移植 `design_brief`、资源池接地、CEFR / 干扰项教学法块。
- 不 import、不复制 GUI 的 Python 代码；只移植契约与 prompt 语义（ADR 0032 的边界不变）。
- 练习只允许**文本题型**：`showWord`（inline term/translation）、`multipleChoice`、`multiSelect`、`fillBlank`、`translateSentence`、`reorderSentence`、`readingMcq`、`readingTrueFalse`、`readingShortAnswer`。`listenAndPick` / `typeTheWord` / `listenOnly` 需要预生成音频或词表行，生成物没有，禁用。

### 3. 生成在 app 级后台队列里跑

- 新增 `AiPracticeJobQueue`（`@lazySingleton`，挂在 `providers.dart` 的路由之上）：`queued → running(outline → fill i/n → validate) → ready | failed`。
- 同一时间只跑 1 个 job，单 job 内逐课顺序生成；关闭面板、切 tab、去复习都不中断。
- 这是**进程内后台**：不声明 OS 后台服务/通知权限；进程被杀后，下次启动把 `queued/running` 标成 `interrupted`，由用户决定是否重试。
- 进度实时落库，回到 AI Hub 可从行里恢复进度条；练习页「智能练习」格子用角标显示生成中/待练习数量。

### 4. 生成物进「我的练习」库，不直接写课程树

- 新增 `ai_practice_sets` 表（`course.db` v32），保存 section JSON、来源、状态、进度、错误、`pinned`。
- **不写** `sections/units/lessons`：`DatabaseSeeder` 在 `index.json`/`expressions.json` 版本变化时会清空语言课程表，写进去的生成物会丢；同时生成物会污染「学习」页课程树。
- AI Hub 新增「我的练习」：最近 3 条 + 全部列表；支持开始练习、失败重试、取消、删除、多选删除。
- 「存放」= 置顶保留（`pinned`），免于保留策略清理；**不是**「写入课程树」。当前保留策略：未存放的 ready 最多 20 条，未存放的 failed/interrupted 保留 7 天。
- 开练页从库里的 section JSON 直接构造 `Lesson` 并走 `LessonViewModel.loadLessonInstance`（与 Daily Challenge 同一条合成课路径），因此不依赖课程树；完成时只显示答题统计，不调用 `LessonCompletionCoordinator`（不污染课程完成度/成就）。

### 5. 退役旧路径

- 删除 `SrsTutorProvider` / `TutorLaunchSheet`（被生成 sheet + 队列取代）。
- 删除 `AiWishProvider` / `AiWishChatPage`（被「自定义课程」表单取代）；`ContentAuthoringMovedBody` 仍服务教材导入 tombstone。
- 课程生成/改课/教材导入的 JSON prompt 仍不开放给用户改写；只有伴学类文本提示词在「系统提示词」面板里可追加。

## 理由

- 课时内 AI 编辑把「生成」和「学习」混在同一个入口，用户无法在生成期间做别的事，且单题级 chip 强制模型改写整节课，语义不清。
- 两条生成路径（`AiCourseProvider.generate` 单次全量、`SrsTutorProvider.tutorPlan` 自带 prompt）已经出现 schema 与规则漂移；一份 section 契约 + 分阶段管线才能让「练习」和「课程」共享校验与重试。
- `course.db` 的课程表是派生缓存（seeder 会重建）。用户生成物必须放在不被 reseed 清掉、且不参与课程树投影的表里。
- 进程内队列已经满足「不退出 app 前台、可以在 app 内干别的」；引入 OS 后台服务会带来通知权限、厂商保活和额度消耗问题，收益不成比例。

## 影响与边界

- 「内容创作退场」的口径只对**内置课程的结构编辑**继续成立；app 内重新提供「生成练习/课程草稿」，但草稿不进课程树、不能替代 `tool/gui` 的完整创作能力。
- 现有用户 `sections` 里历史 AI 生成小节不做自动迁移（没有可靠 marker）；它们仍留在课程树，后续可用显式清理工具处理。
- 生成成本 = `1 + units × lessons` 次 JSON 调用（可选 +1 次说明）；自定义课程在开始前显示预计调用数。
- 生成的练习完成只记错题/SRS/学习统计，不记课程完成度、不发课程宝石。
- 新增表随 `course.db` 进入 WebDAV 备份；本地 JSON 导出当前不含 `course.db`，不额外导出练习库。

---

## 修订 2026-10-21 — 双表收纳、一周过期、内容核验

> 修订 §4（生成物进「我的练习」库）的存储与保留策略，并新增内容核验门禁。
> 契约（§2）、队列形态（§3）、退出旧路径（§5）不变。

### R1. 一张平表 → 合集 + 版本（`ai_courses` / `ai_course_versions`，v33）

`ai_practice_sets` 把「任务生命周期」和「收藏内容」挤在同一行：重新生成会覆盖旧内容，
库里也没有目录层级。改为：

- `ai_courses`：合集身份——标题、语言、来源、难度、主题、`pinned`、`expires_at_ms`；
- `ai_course_versions`：每次生成一条——状态、section JSON、请求快照、核验报告、进度。

新版本追加而不是覆盖，`playableVersion` 取最新可玩版本：一次失败的重新生成不会把上一版
能用的内容藏起来。v32 的旧行在迁移时 1:1 拆成「1 合集 + 1 版本」，`pinned` 照搬。

### R2. 保留策略：一周过期，收藏永久

- 草稿的 `expires_at_ms = created_at + 7 天`，**从创建算**，不是从最后一次使用算——滚动
  时钟会让「一周后过期」这句话对用户不可预测。
- 收藏（`pinned`）清空 `expires_at_ms`，永久保留；取消收藏时给一个新的 7 天窗口，避免
  「取消收藏当场消失」。
- 清理只看截止时间：`pinned = 0 AND expires_at_ms <= now`。原来的
  `keepReady = 20` 上限删除——它会比「一周」更早静默删掉内容。
- 清理时机从「仅冷启动」扩到「冷启动 + 打开库页」，长会话也守约。

### R3. 内容核验门禁（`AiPracticeQualityChecker`）

`CourseValidator` 只校验契约（id 能解析、模板已知、引用存在），对「这题能不能答」一无所知：
选项全相同、`correctIndex` 越界（渲染时 `options[correctIndex]` 直接抛 `RangeError`）、
填空句里没有空格、排序题词块与答案不一致、整段生词覆盖率 0，全都能过。

新增纯 Dart 的两级核验：

- **阻断级**（修不好就判失败，不进库）：占位文本、空题干/空答案、选项 < 2、选项重复、
  正确下标越界、填空缺 `___`、排序词块与答案不一致、阅读课没有正文、空阶段/空课时、
  生词从未出现在任何课时。
- **提示级**（写入核验报告并在详情页展示，绝不阻断）：选项数不等于 4、单阶段题量 < 3、
  题干重复、排序未打乱、填空答案未原样出现在句中（黏着语会变形）。

单课修复预算从 1 次提到 2 次；整节再过一次核验（含生词覆盖）。报告存进
`ai_course_versions.quality_json`，详情页展示。

### R4. 库的收纳面

- 库页三段：**收藏 · 永久保存** / **草稿**（带「还剩 N 天」，≤2 天高亮）/ **生成任务**。
  失败与进行中的任务不再混进「我的练习」正文。
- 卡片上加一键收藏（`star`）与剩余天数；新增课程详情页：目录（单元 → 课时 → 题量）、
  核验报告、生成历史、重新生成。
- AI Hub 预览只摆收藏与即将过期，任务只显示一行计数。
