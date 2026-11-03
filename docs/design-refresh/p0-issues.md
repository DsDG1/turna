# P0 问题列表与截图场景（设计翻新 · 全 App 重设计）

> 「湿地雾光」全 App 重设计计划的 P0 交付物之一。问题按「是否阻断设计开工」分级：A 类必须先修或先决定，B 类是新版设计的核心抓手（与计划第 9 节风险表对应），C 类顺手修。逐页明细见 [p0-structure.md](./p0-structure.md) 各族「共性问题」小节。

## A 类：设计开工前必须处理

| # | 问题 | 证据落点 | 处理 |
|---|---|---|---|
| A1 | **已修复** · 原断链路由：`AiPracticeDetailRoute` 已在 `routing.dart` 注册（带课程守卫，与练习库/运行页一致），生成类本就存在，无需 codegen | `views/ai/ai_practice_library_page.dart`、`views/ai/components/ai_practice_library_section.dart`（push 侧）；`routing/routing.dart`（已补注册） | 已销项；后续随 AI 域重设计一并复核 |
| A2 | **已处置** · 原五项待处置：SectionPickerPage / ChangelogRoute / OfficialAnkiMappingPage 的路由与页面删除（功能分别被章节弹层、关于页 Tab、quick/mcq 两个内联 sheet 取代）；DailyChallengePage 恢复练习台工具格入口；UnifiedReviewRoute 保留并标注「仅深链兜底」；ContentUpdateDialog 死组件删除、developer lab 过期注释清除 | `routing/routing.dart`、`views/play/play_hub_screen.dart`、`views/settings/changelog_page.dart` 等 | 已销项（明细见 `test/BASELINE.md` 当日条目） |
| A3 | **鸿蒙 chrome 契约隐式**：正式记忆卡会话在鸿蒙无 AppBar/进度头/工具栏/评分栏（原生 ability 盖面），卡面舞台整 build 分叉。新版面若按 Android 形态画全套 chrome，鸿蒙会被画上不可用按钮 | `views/anki/anki_review_session_page.dart`、`views/anki_official/official_anki_reviewer_stage.dart` | 新版线框为该会话显式出「双平台 chrome 对照」，宿主外壳只设计 Android 侧 + 鸿蒙原生侧边界说明 |

## B 类：全 App 级设计问题（新版设计抓手）

| # | 问题 | 表现位置 |
|---|---|---|
| B1 | **顶栏信息堆叠**：课程切换入口 + 分数/连签/宝石/待复习四胶囊塞进 60px 顶栏，横滚兜底溢出无提示；待复习聚合 5 个数据源 | `views/home/components/stat_app_bar.dart`（对应计划 R01「状态数字进入所属页面」） |
| B2 | **会话外壳三套并存**：统一复习、语法自研状态机、课时会话壳三份复制（进度条样式、评分条、完成体验互不相同）；完成页三轨制（玻璃完成卡 / 纯文本居中 / 课时弹窗） | `views/review/unified_review_page.dart`、`views/review/grammar_review_screen.dart`、`views/review/components/review_components.dart`、`views/lesson/components/lesson_dialogs.dart`；同构复制：每日挑战 / 弱词 / 错题复习三页 |
| B3 | **课时内主 CTA 位置三套**：底栏按钮 / 滚动内容自画按钮 / 整卡点击；揭示型题型提交后残留禁用按钮与底栏双按钮同屏 | `views/lesson/components/interactions/`（listen_only、anki_card、show_word、image_recall 等） |
| B4 | **正误反馈无统一区域**：选项染色 + 答错才有的横幅插在滚动内容尾部；答对无文案层反馈 | 同上 + `interaction_renderer.dart` |
| B5 | **卡面语言至少五种并存**：SoftCard 玻璃皮 / flatPaper 手写同构容器 / 裸 Material Card / AiGroupCard 旧软彩卡 / 存储页自绘硬编码字号 | `views/widgets/turna_cards.dart` 使用面 vs `views/review/review_source_detail_page.dart`、`views/ai/components/ai_sheet_widgets.dart`、`views/settings/storage_diagnostics_page.dart` |
| B6 | **失败态缺失清单**：学习洞察 FutureBuilder 无 error 分支（出错停 spinner）、牌组统计同（异常无限转圈）、学习统计同、错题两页无失败态、语法评级失败无 UI、修复中心吞 doctor 异常、AI 预览 bootError 无重试 | `views/review/learning_insights_page.dart`、`views/anki/anki_deck_stats_page.dart`、`views/profile/widgets/learning_stats.dart`、`views/anki_official/official_anki_repair_center_page.dart`、`views/anki_official/official_anki_reviewer_page.dart` |
| B7 | **视觉暗示与出口语义失真**：来源行带 chevron 整行不可点；课时完成弹层「继续」与「返回课程」回调完全一致 | `views/review/review_progress_page.dart`、`views/lesson/components/lesson_dialogs.dart` |
| B8 | **平台条件入口三种形态并存**：tile 隐藏（AI/跟读/远程备份）、tile 禁用并解释（每日提醒）、页内兜底卡（远程备份直开）——无统一决策规则 | `views/settings/pages/`、`views/settings/widgets/`、`views/settings/remote_backup_page.dart` |
| B9 | **说明页三胞胎组件重复**：关于/隐私/透明日志各自维护同构 `_AboutCard`/`_SectionHeader` 副本（更新日志第四份） | `views/settings/about_turna_page.dart`、`privacy_details_page.dart`、`transparency_log_page.dart`、`changelog_page.dart` |
| B10 | **搜索/防抖/懒加载重复实现**：词典与卡牌浏览器各写一份 250ms 防抖 + 线性扫描；浏览器逐行懒加载私有 | `views/dictionary/dictionary_page.dart`、`views/anki/anki_card_browser_page.dart` |
| B11 | **键盘处理散落**：课时页无页面级 scroll-into-view / 底栏适配，5 个文本题型各自 autofocus/unfocus | `views/lesson/new_lesson_screen.dart` + 5 个文本 renderer |
| B12 | **玻璃档位口径跨域不一致**：ADR 0063 的档位约定只在设置域靠组件默认值成立；个人域用旧档、成就详情用旧式描边 | `views/profile/`、`views/settings/widgets/primitives/settings_section.dart` |
| B13 | **AI 域视觉割裂 + 断链衍生**：四套卡面语言、未配置/错误呈现三路并行、深链可绕过平台裁剪（防护全压引擎层） | `views/ai/` 全域（A1 修复后重验） |

## C 类：顺手修（不阻断设计）

| # | 问题 | 位置 |
|---|---|---|
| C1 | 硬编码中文绕过 AppStrings：牌组目录树「个章节节点 / 张卡片」、映射页「（共 N 张）」、生成 sheet 模板名与错误文案、练习运行「答对 x/y」 | `views/anki/import_wizard/deck_directory_tree_view.dart`、`views/anki_official/official_anki_mapping_page.dart`、`views/ai/components/ai_practice_generate_sheet.dart`、`views/ai/ai_practice_run_page.dart` |
| C2 | 过期注释：Advanced 页尾注与路由注释提及的 developer lab 路由已不存在 | `views/settings/widgets/settings_advanced_section.dart`、`routing/routing.dart` |
| C3 | 章节弹层数量副标题由进度字符串拆词拼出 | `views/courses/components/section_bottom_sheet.dart` |
| C4 | API 配置页探测错误分类的字符串包含匹配存在运算符优先级隐患 | `views/ai/ai_api_config_page.dart` 的 `_classifyProbeError` |

## 截图场景清单（可重复采集口径）

固定口径：**debug 构建 · Pixel 6 / Android 15 模拟器 · 内置课程播种完成 · 主题按场景**。每张截图记录：构建、设备、主题、内容状态、触发步骤。上一轮组件级收口已留下 20 张主路径截图（`dist/design-refresh/screenshots/`，覆盖：四主 Tab 浅色、词典输入与无结果、深色练习与设置、200% 字号 + 高对比、课程树展开、课时进入/作答/反馈/拼句/键盘输入/完成/返回进度）——**可直接复用为旧版基线**，本轮 P0 不重复采集。

P1 开工需补采的缺口场景：

| 场景 | 触发要点 | 覆盖目标 |
|---|---|---|
| 听力 / 跟读 / 阅读 / 翻面卡题型 | 各选一课时或构造内容 | R05 剩余题型版面 |
| 统一复习会话全程 | 揭示 → 评分 → 完成 → 再来一批 | R08 |
| 语法复习三相 / 错题复习 / 每日挑战（若 A2 决定给入口） | 三壳对比 | R07 / R08 |
| 错题列表 + 仪表盘 | 有错题数据与空态各一 | R09 |
| 洞察 / 进度 / 来源详情 | 有数据 + 稀疏数据 | R10 |
| 记忆卡导入向导五步 | 含预览目录树与 blocking 态 | R12 |
| AI Hub / 练习库 / 聊天 / 配置 | 未配置与已配置各一 | R14 |
| 成就 / 头像环 / 分享预览 | 新用户与长期数据 | R15 |
| 设置落地页 + 至少三个分类页 | 含 200% 字号 | R16 |
| 系统健康 / 存储诊断 / 远程备份 | 含空态 | R17 |
| 失败态采样：断网点课程更新、AI 生成失败、复习写失败 | 各触发一次 | B6 对照 |
| 键盘遮挡采样：翻译题 + 词典搜索 + 聊天输入 | 小屏 | B11 对照 |
| 鸿蒙伴生版主路径（设备允许时） | 会话宿主原生盖面形态 | A3 对照 |

> 本轮 P0 未新增设备截图：工作区存在大量未提交功能改动，采集安排在 P1 开工时按上表口径一次采齐，避免基线混入中间态。
