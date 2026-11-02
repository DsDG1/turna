# ADR 0064 — 子课提升为课程树节点与独立会话

> 状态：已接受 ｜ 日期：2026-11-02
>
> 真源：`lib/views/courses/course_tree.dart`（节点扁平化）、`lib/application/lesson_viewmodel.dart`（`_targetedSubLessonSession` / 结算门）、`lib/data/course_database.dart`（v34 迁移）
>
> 关联：`docs/authoring/lesson-type-templates.md`「子课（subLesson）体量契约」（播放形态段由本 ADR 改写）

## 背景

多子课的课（intro / practice / review 模板）此前在课程树上是一个节点，点进去顺序连打全部子课，中间只弹一个「小课 k/n 完成」暂停框。用户感知是一节「大课」：进度条与题号按整课累计（例：2 子课 × 13 题 = 一锅 26 题），子课在树上不可见、不可单独选择或重玩。

同时，子课完成持久化（`completedSubLessonIds`）、段差值统计、断点续玩已经存在——缺的只是入口粒度与结算口径。

## 决策

### 1. 树粒度：每个子课一个可玩节点

课程树的旅程行按「可玩节点」扁平化：`subLessonSummaries.length ≥ 2` 的课渲染为**组头行 + N 个子课瓦片**；1 节或 0 节的课仍是一个瓦片（拆组门槛与播放侧一致）。组头行承载课名、课型图标、「小课 k/n」进度与 due/weak 角标（`LessonLinkStore` 保持课粒度，角标不拆）；子课瓦片以子课名为标题、序号为徽标，点击进入**只玩这一节**的独立会话。

### 2. L1 元数据通道：`lessons.sub_lesson_summaries` 列（schema v34）

课程树（L1）刻意不加载课体（`CourseRepository.section()` 不 join `lesson_contents`）。子课节点需要 id/name，走**独立摘要列**而非填充 `content.subLessons`——后者会让 `LessonViewModel._lessonHasBody` 把 L1 行误判为可播放，绕过 L2 装载。列由 `SubLessonSummariesCodec` 单点编解码，两个写入方（`DatabaseSeeder`、`AiCourseProvider`）播种时从已解析体派生；v34 迁移从存量 `content_json` 回填，无需重播种。摘要字段在 `Lesson` 上排除 JSON 序列化（section JSON 线格式零变化）。

### 3. 会话形态：合成单子课实例

`loadLesson(lessonId, subLessonId:)` 载入完整 L2 课后，合成「只含该子课」的实例（`copyWith` 出 1-子课副本）交给既有单段机制——计数、进度条、undo、完成弹窗全部自动会话化；副本的唯一 segment 自带 `subLessonId`，完成清扫自动记录该节点。未指定 `subLessonId` 的装载（旧链式路径、AI 练习的内存课）行为不变。会话结束复用既有完成弹窗，弹窗本就无条件 pop——「结束即回课程树」零新动线。

### 4. 经济：每会话发奖，课级结算门控

**会话是发奖单位**：每次子课会话结束都发 10 XP + 5 宝石（全对追加 15 + 10），宝石幂等键编入 `subLessonId`（`earn:lesson:<lessonId>:<subLessonId>:<day>`，否则同课多子课同日互相去重只发一次）。**课级记录走结算门**：仅当本会话补齐最后一节未完成子课、且进入时整课未完成，才 `recordLessonCompletion`；「完美课」= 全部子课各自完美（`perfectSubLessonIds` 新增持久集）。已完成的课重玩子课：照常发奖，永不重结算。平面课 / 单子课课完全走原路径（数值零变化）。

### 5. 兼容与持久化补漏

旧记录（整课完成、无子课记录）显示层一律视为「全部子课节点完成」（`_nodeCompleted` 覆盖），next-up 跳过整组。子课进度键 `completedSubLessonIds` / `perfectSubLessonIds` 补进备份清单与恢复链（此前 `completedSubLessonIds` 不在备份 manifest，是既有进度丢失面）。

## 明确不做

- 不改 section JSON 数据格式、validator、AI prompt 管线、`tool/gui`（数据模型未变）。
- 不拆 due/weak 角标到子课粒度（链是课粒度，拆链是独立议题）。
- mastery / listening / Official Anki v2 课时天然单段，不参与拆分。
- 单元卡进度环保持课粒度。
