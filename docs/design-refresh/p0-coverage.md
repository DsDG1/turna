# P0 页面覆盖表（设计翻新 · 全 App 重设计）

> 「湿地雾光」全 App 重设计计划的 P0 交付物之一。真源计划见 [app-design-refresh-plan.md](../app-design-refresh-plan.md)。本表覆盖全部实际页面、路由、Tab 内嵌页、非路由页与全局弹层，并给出处置分类；逐页旧版结构见 [p0-structure.md](./p0-structure.md)，资产与问题见同目录另两篇。
>
> 本表与上一轮组件级收口的覆盖表（`dist/design-refresh/` 交付记录）不互斥：那一轮落地的是材质与公共组件口径，本轮要求逐页结构重设计，页面以本表为准重新逐项交付。

## 读法

- **入口**：正常用户路径怎么到达。「无生产入口」= 路由已注册但 `lib/` 内无任何 push 调用（深链仍可达）。
- **平台与守卫**：仅列影响可达性或形态的条件——`isDegraded(OhosDegradation.*)`（鸿蒙伴生版降级，ADR 0056 / 0047）、`DiagnosticsReleaseGuard`、`CourseReadyGuard`。
- **处置分类**：`生产` / `条件生产`（平台或配置裁剪后可达）/ `调试诊断`（仅 debug 或诊断构建）/ `无生产入口`（待处置决定）/ `断链`（必须修）/ `非路由页`。

## 页面清单（按 R01–R18 页面族）

### R01 启动与外壳

| 页面 / 组件 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| SplashPage | `SplashRoute`（initial）· `views/splash/splash_page.dart` | 冷启动 | TTS 提示在鸿蒙走只读说明对话框 | 生产 |
| HomePage 外壳 | `HomeRoute` · `views/home/home_page.dart` | Splash 替换 | CourseReadyGuard | 生产 |
| StatAppBar（学习顶栏） | 组件 · `home/components/stat_app_bar.dart` | Tab 0 激活时 | — | 组件（重设计重点） |
| BottomNavigator / ScrollHideBar / TabStack | 组件 · `home/components/` | 外壳常驻 | 高对比/专注模式跳过磨砂 | 组件（重设计重点） |

### R02 课程主线

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| CourseTree | Tab 0 内嵌 · `views/courses/course_tree.dart` | 默认 Tab | — | 生产 |

### R03 课程选择与管理

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| CourseManagementPage | `CourseManagementRoute` · `views/courses/course_management_page.dart` | StatAppBar 地球图标 / 课程树空态 / 导入完成「查看牌组」 | CourseReadyGuard | 生产 |

> SectionPickerPage 原列于此：路由与页面已在 A2 处置中删除（功能被章节底部弹层完全取代）。

### R04 课时骨架

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| NewLessonPage | `NewLessonRoute` · `views/lesson/new_lesson_screen.dart` | 课程树课时/子课瓦片 | AI 提示按钮鸿蒙隐藏 | 生产 |

### R05 题型 renderer（17 个，随课时渲染）

| 文件（`views/lesson/components/interactions/`） | 题型 | 平台与守卫 |
|---|---|---|
| multiple_choice_renderer.dart | 单选 | — |
| multi_select_renderer.dart | 多选 | — |
| fill_blank_renderer.dart | 填空 / 选择填空 | — |
| translate_sentence_renderer.dart | 翻译造句 | — |
| listen_and_pick_renderer.dart | 听音选图/词 | — |
| type_the_word_renderer.dart | 听写打字（带题面） | — |
| listen_only_renderer.dart | 听力小结 | — |
| show_word_renderer.dart | 生词展示卡 | — |
| anki_card_renderer.dart | 翻面卡 | — |
| image_recall_renderer.dart | 看图回忆 | — |
| dictation_renderer.dart | 听写（无题面） | — |
| reorder_sentence_renderer.dart | 拼句排序 | — |
| reading_mcq_renderer.dart | 阅读选择 | — |
| reading_true_false_renderer.dart | 阅读判断 | — |
| reading_short_answer_renderer.dart | 阅读简答 | — |
| read_aloud_renderer.dart | 跟读 | 鸿蒙识别器降级走 `_DegradedBody`（ADR 0061） |
| anki_html_card_retired_renderer.dart | 已退役 HTML 卡占位 | — |

### R06 完成体验

| 组件 / 弹层 | 文件 | 入口 | 处置 |
|---|---|---|---|
| 课时完成 / 小课检查点 / 掌握重试三弹层 | `views/lesson/components/lesson_dialogs.dart` | 课时与小课结算 | 生产（弹层） |
| UnifiedReviewCompletion | `views/review/components/` | 统一复习与正式记忆卡完成 | 生产（组件） |
| AchievementFeedbackBanner | `views/profile/achievements/` | 完成页与课时弹层内 | 生产（组件） |

### R07 练习入口与每日挑战

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| PlayHubScreen | Tab 1 内嵌 · `views/play/play_hub_screen.dart` | 底部导航 | 智能练习 tile 鸿蒙不渲染；Anki 课裁剪单词/语法/词典/弱词入口 | 生产 |
| PlayAppBar | 组件 · `views/play/play_app_bar.dart` | Tab 1 激活时 | — | 组件 |
| DailyChallengePage | `DailyChallengeRoute` · `views/play/daily_challenge_screen.dart` | 练习台「练习工具」格（A2 恢复入口；Anki 牌组课不渲染） | — | 生产 |
| WeakWordsPage | `WeakWordsRoute` · `views/play/weak_words_page.dart` | Play Hub 工具行 | Anki 课时入口隐藏 | 生产 |

### R08 复习会话

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| UnifiedReviewPage | `UnifiedReviewRoute`（路由无 push）· `views/review/unified_review_page.dart` | SrsReviewPage 以 widget 嵌入（活路径） | AI 讲解按钮鸿蒙隐藏 | 条件生产（组件路径） |
| SrsReviewPage | `SrsReviewRoute` · `views/review/srs_review_screen.dart` | Play Hub 队列格/Hero、复习进度、资料页快捷 | CourseReadyGuard | 生产 |
| GrammarReviewPage | `GrammarReviewRoute` · `views/review/grammar_review_screen.dart` | Play Hub、资料页、错题列表 | — | 生产 |
| MistakeReviewPage | `MistakeReviewRoute` · `views/review/mistake_review_page.dart` | Play Hub 队列格+Hero、资料页 | CourseReadyGuard | 生产 |
| AnkiReviewPage（复习中枢） | `AnkiReviewRoute` · `views/anki/anki_review_screen.dart` | 复习来源详情「开始复习」 | CourseReadyGuard；legacy 源 due 恒 0 | 生产 |
| AnkiReviewSessionPage（正式会话宿主） | `AnkiReviewSessionRoute`（统一经 `FormalReviewLauncher`）· `views/anki/anki_review_session_page.dart` | 复习中枢 / 浏览器 / Play Hub / 资料页 | **鸿蒙无 AppBar/进度头/工具栏/评分栏（原生 ability 盖面）** | 生产 |

### R09 错题

| 页面 | 路由 · 文件 | 入口 | 处置 |
|---|---|---|---|
| MistakeListPage | `MistakeListRoute` · `views/review/mistake_list_page.dart` | MistakeReview 顶栏列表图标 | 生产 |
| MistakeDashboardPage | `MistakeDashboardRoute` · `views/review/mistake_dashboard_page.dart` | MistakeList 顶栏洞察图标 | 生产 |
| MistakePracticePage | `MistakePracticeRoute` · `views/review/mistake_practice_screen.dart` | MistakeList 卡片「练习」 | 生产 |

### R10 进度与洞察

| 页面 | 路由 · 文件 | 入口 | 处置 |
|---|---|---|---|
| ReviewProgressPage | `ReviewProgressRoute` · `views/review/review_progress_page.dart` | Play Hub 工具行、资料页 | 生产 |
| LearningInsightsPage | `LearningInsightsRoute` · `views/review/learning_insights_page.dart` | 复习进度页顶栏 + 底部按钮 | 生产 |
| ReviewSourceDetailPage | `ReviewSourceDetailRoute` · `views/review/review_source_detail_page.dart` | 学习洞察来源行 chevron | 生产 |

### R11 词典

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| DictionaryPage | `DictionaryRoute` · `views/dictionary/dictionary_page.dart` | Play Hub 工具行 | AI 富集按钮鸿蒙隐藏；CourseReadyGuard | 生产 |

### R12 记忆卡导入与适配

| 页面 / 步骤体 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| AnkiImportPage（向导壳） | `AnkiImportRoute` · `views/anki/anki_import_screen.dart` | 复习中枢上传按钮 / 课程管理添加卡 | — | 生产 |
| 预览步骤体 ModernAnkiImportPreview 及配套 | `views/anki/import_wizard/`（目录树、预设选择、notetype 行、样本 sheet、正面选择 sheet、中断横幅） | 向导 Previewing 步 | SmartAdaptation 区鸿蒙不渲染 | 生产（步骤体） |
| AnkiImportDoneStep | `views/anki/import_wizard/anki_import_done_step.dart` | 向导 Completed 步 | — | 生产（步骤体） |

> OfficialAnkiMappingPage 原列于此：路由与页面已在 A2 处置中删除（流程被 quick/mcq 两个内联 sheet 取代，底层建议投影由 application 层测试继续覆盖）。

### R13 记忆卡管理与宿主

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| AnkiCardBrowserPage | `AnkiCardBrowserRoute` · `views/anki/anki_card_browser_page.dart` | 复习中枢牌组卡「浏览牌组」 | 非 Official 源 fail-closed 文案 | 生产 |
| AnkiDeckStatsPage | `AnkiDeckStatsRoute` · `views/anki/anki_deck_stats_page.dart` | 复习中枢牌组卡「统计」 | — | 生产 |
| OfficialAnkiRepairCenterPage | `OfficialAnkiRepairCenterRoute` · `views/anki_official/official_anki_repair_center_page.dart` | 课程管理顶栏 / 存储诊断链接 | — | 生产 |
| OfficialAnkiReviewerPage（单卡内部预览） | `OfficialAnkiReviewerRoute` · `views/anki_official/official_anki_reviewer_page.dart` | 深链 / 调试入口 | **DiagnosticsReleaseGuard：release 默认拦回 Home** | 调试诊断 |
| OfficialAnkiReviewerStage / View（卡面舞台与 PlatformView 宿主） | 同目录组件 | 内嵌于正式会话与预览页 | 鸿蒙走原生 ability；非 Android/iOS 平台错误面 | 生产（组件，重设计只动外壳） |

### R14 AI

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| AiHubPage | `AiHubRoute` · `views/ai/ai_hub_page.dart` | Play Hub 智能练习 tile（鸿蒙不渲染 tile；**路由无 guard，深链可达**） | CourseReadyGuard | 条件生产 |
| AiPracticeLibraryPage | `AiPracticeLibraryRoute` · `views/ai/ai_practice_library_page.dart` | Hub「我的练习」查看全部 | 同上 | 条件生产 |
| AiPracticeRunPage | `AiPracticeRunRoute` · `views/ai/ai_practice_run_page.dart` | 练习库「开始」 | — | 条件生产 |
| AiPracticeDetailPage | `AiPracticeDetailRoute`（已注册，带课程守卫）· `views/ai/ai_practice_detail_page.dart` | 练习库 / Hub 预览卡「详情」菜单 | — | 生产（断链已修复） |
| AiTutorChatPage | `AiTutorChatRoute` · `views/ai/ai_tutor_chat_page.dart` | Hub 伴学宫格 / 指南卡 / 最近任务 | — | 条件生产 |
| AiHintChatPage | `AiHintChatRoute` · `views/ai/ai_hint_chat_page.dart` | 课时 AI 提示 sheet「进入对话」/ 最近任务 | 课时按钮鸿蒙隐藏 | 条件生产 |
| AiDiagnosisPage | `AiDiagnosisRoute` · `views/ai/ai_diagnosis_page.dart` | Hub 伴学宫格 / 指南卡 | — | 条件生产 |
| AiSavedListPage | `AiSavedListRoute` · `views/ai/ai_saved_list_page.dart` | Hub 伴学宫格 / 指南卡 | — | 条件生产 |
| AiApiConfigPage | `AiApiConfigRoute` · `views/ai/ai_api_config_page.dart` | Hub hero / 未配置面板 / 错误横幅 / 设置-高级（鸿蒙隐藏 tile） | — | 生产 |
| AiFeatureGuidePage | `AiFeatureGuideRoute` · `views/ai/ai_feature_guide_page.dart` | Hub 顶栏帮助 | — | 条件生产 |
| TextbookImportPage（tombstone） | `TextbookImportRoute` · `views/ai/textbook/textbook_import_page.dart` | Hub 最近任务继续行（唯一活入口） | — | 条件生产（低频） |
| ContentAuthoringMovedBody | 无路由 · `views/ai/content_authoring_moved_page.dart` | 被 TextbookImportPage 内嵌（全库唯一使用点） | — | 组件（可并入调用方） |

### R15 个人与成就

| 页面 | 路由 · 文件 | 入口 | 处置 |
|---|---|---|---|
| ProfilePage | Tab 2 内嵌 · `views/profile/profile_screen.dart` | 底部导航 | 生产 |
| AchievementsPage | `AchievementsRoute` · `views/profile/achievements_page.dart` | 资料页入口行 | 生产 |
| AvatarRingsPage（装饰商店） | `AvatarRingsRoute` · `views/settings/avatar_rings_page.dart`（位于 settings 目录、个人域内容） | 设置-账户分类 | 生产 |

### R16 设置

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| SettingsPage（落地页） | Tab 3 内嵌 · `views/settings/settings_page.dart`（内层自持 Scaffold AppBar，外壳槽位是零高 stub） | 底部导航 | — | 生产 |
| Account / Learning / AppearanceSound / Accessibility / DataBackup / Advanced / LegacyCompatibility / About 八分类页 | 各 `Route` · `views/settings/pages/` | 落地页分组卡与快捷格 | AI 连接 tile 鸿蒙隐藏；跟读 tile 鸿蒙隐藏；远程备份 tile 鸿蒙隐藏 | 生产 |

### R17 备份、更新与诊断

| 页面 | 路由 · 文件 | 入口 | 平台与守卫 | 处置 |
|---|---|---|---|---|
| RemoteBackupPage | `RemoteBackupRoute` · `views/settings/remote_backup_page.dart` | 数据备份分类 tile | 鸿蒙 tile 隐藏 + 页内兜底卡 | 条件生产 |
| SystemHealthPage | `SystemHealthRoute` · `views/settings/system_health_page.dart` | 高级分类 | — | 生产 |
| StorageDiagnosticsPage | `StorageDiagnosticsRoute` · `views/settings/storage_diagnostics_page.dart` | 高级分类 | — | 生产 |
| StorageCategoryItemsPage | **非路由**（`platformPageRoute` 手工 push + bool 返回协议）· `views/settings/storage_category_items_page.dart` | 存储诊断两类下钻 | — | 非路由页 → 重设计时定路由化与否 |
| TransparencyLogPage | `TransparencyLogRoute` · `views/settings/transparency_log_page.dart` | 系统健康 / 隐私页浮出 pill | — | 生产 |
| 课程更新 tile（URL OTA）/ 课程恢复 tile | 组件 · `views/settings/components/` | 学习偏好卡 | — | 生产（组件） |

### R18 说明与全局反馈

| 页面 | 路由 · 文件 | 入口 | 处置 |
|---|---|---|---|
| AboutTurnaPage（双 Tab，内嵌更新日志） | `AboutTurnaRoute` · `views/settings/about_turna_page.dart` | 设置-关于分类 | 生产 |
| PrivacyDetailsPage | `PrivacyDetailsRoute` · `views/settings/privacy_details_page.dart` | 设置-关于 / 关于页隐私 tile | 生产 |

> ChangelogPage 独立路由原列于此：已在 A2 处置中删除（主入口是关于页「更新日志」Tab 内嵌）；`ChangelogPage` 转为机制 holder（`abstract final class`），渲染与剪贴板逻辑保留。

## 全局弹层清单

### 底部 sheet

| Sheet | 文件 | 触发点 | R |
|---|---|---|---|
| SectionBottomSheet | `views/courses/components/section_bottom_sheet.dart` | 课程树吸顶章节头 | R02 |
| showReadingPassageSheet | `views/lesson/components/lesson_stage_widgets.dart` | 阅读题「展开原文」 | R05 |
| AiHintSheet / AiDepthTutorSheet | `views/lesson/components/ai_hint_sheet.dart`、`ai_depth_tutor_sheet.dart` | 课时 AI 提示 / 深度讲解 | R04 / R14 |
| AiPromptSheet（系统提示词） | `views/ai/ai_prompt_sheet.dart` | Hub 底部工具 | R14 |
| showAiPracticeGenerateSheet | `views/ai/components/ai_practice_generate_sheet.dart` | Hub / 练习库 / 诊断页 / 指南 | R14 |
| showAiCardExplainSheet | `views/ai/components/ai_card_explain_sheet.dart` | 统一复习讲解按钮（鸿蒙隐藏） | R08 |
| showMcqPreviewSheet / showQuickFrontPicker | `views/anki/import_wizard/mcq_preview_sheet.dart`、`quick_front_picker_sheet.dart` | 导入预览 | R12 |
| showAdaptationRestoreSheet | `views/anki_official/components/adaptation_restore_sheet.dart` | 课程管理官方源条目 | R12 |
| _DictionaryAiSheet | `views/dictionary/dictionary_page.dart` 内嵌 | 词条 AI 按钮（鸿蒙隐藏） | R11 |
| showAvatarPickerSheet / _EditNameSheet | `views/profile/widgets/avatar_picker_sheet.dart`、`account_app_bar.dart` | 资料 hero 头像 / 编辑 | R15 |
| _ShareProgressSheet | `views/home/components/profile_app_bar.dart` | 资料 hero 分享 | R15 |
| showAchievementDetailSheet | `views/profile/achievements/achievement_detail_sheet.dart` | 成就徽章 / 推荐卡 | R15 |
| _CourseTtsSettingsSheet | `views/courses/course_management_page.dart` 内嵌 | 课程卡溢出菜单 | R03 |
| tutor 会话列表 sheet | `views/ai/ai_tutor_chat_page.dart` 内嵌 | 聊天页顶栏 | R14 |

### 对话框与浮层

| 弹层 | 文件 / 位置 | 触发点 | R |
|---|---|---|---|
| TTS 可用性引导 | `views/splash/splash_page.dart` 的 `maybePromptTtsAvailability` | 会话首次（鸿蒙走只读变体） | R01 |
| StreakBrokenDialog | `views/home/streak_broken_dialog.dart` | 断签且未被 TTS 弹层占用预算 | R01 |
| 内容更新 banner + 重置确认（内嵌 AlertDialog） | `views/home/home_page.dart` | 课程内容版本变化且有进度 | R01 |
| 课时退出确认 / 完成三弹层 | `views/lesson/new_lesson_screen.dart`、`components/lesson_dialogs.dart` | 课时流程 | R04 / R06 |
| 统一复习退出确认 | `views/review/unified_review_page.dart` | 会话中退出 | R08 |
| 导入三阶段进度 / 替换确认 / 错误对话框 | `views/courses/course_management_page.dart`、`views/anki/anki_import_screen.dart` | pack 导入 / Anki 导入 | R03 / R12 |
| 卸载确认 / 每日上限 / 中断导入丢弃确认 | `views/anki/anki_review_screen.dart`、`import_wizard/official_pending_import_banner.dart` | 牌组管理 | R12 / R13 |
| AI 确认族（删除练习 / 恢复默认 / 清除凭据 / 恢复默认连接） | `views/ai/` 各页 | 危险操作 | R14 |
| 设置确认族 SettingsConfirmDialog / InfoDialog / FormDialog | `views/settings/widgets/feedback/settings_feedback.dart` | 危险操作与表单 | R16 / R17 |
| 课程更新 URL 对话框（六阶段状态） | `views/settings/components/settings_course_update_tile.dart` | 手动 OTA | R17 |
| PlayInfoPopup（Overlay 长按浮窗） | `views/play/components/info_popup.dart` | Play Hub 各卡长按 | R07 |
| TurnaSnackBar | `views/widgets/turna_snack_bar.dart` | 全局一次性反馈 | 全部 |

## 处置汇总（P1 前需要明确决定）

| 类别 | 条目 | 建议动作 |
|---|---|---|
| **域边界（[ADR 0067](../decisions/0067-memory-card-returns-to-course-domain.md)）** | 记忆卡回归课程域：牌组即课程，出现在课程管理列表且可切换，从课程管理导入；练习台无记忆卡独立入口，记忆卡中枢页删除；语言课程激活时无记忆卡入口 | 设计约束，已随 P3 / P4 落地 |
| 断链 | `AiPracticeDetailRoute` 被 push 但未注册——**已修复**（已注册，带课程守卫） | 已销项 |
| 无生产入口 | **已处置（A2）**：SectionPickerPage / ChangelogRoute / OfficialAnkiMappingPage 三者路由与页面删除；UnifiedReviewRoute 保留并标注「仅深链兜底」（生产路径是 SrsReviewPage 的 widget 嵌入）；DailyChallengePage 恢复练习台工具格入口 | 已销项（明细见 `test/BASELINE.md` 当日条目） |
| 死组件 | **已处置（A2）**：ContentUpdateDialog 连目录删除；routing 与 Advanced 页的 developer lab 过期注释清除 | 已销项 |
| 非路由页 | StorageCategoryItemsPage（手工 push + bool 协议，无深链/预测性返回） | 重设计路由化或维持并说明 |
| 组件型存在 | ContentAuthoringMovedBody（单一使用点） | 并入调用方 |

计数：路由 51 条（含 initial Splash；A1 补注册详情页、A2 删三个死路由后）；Tab 内嵌页 4；非路由页 1（StorageCategoryItems）；题型 renderer 17；底部 sheet 14 族；对话框/浮层 12 族。全 App 实际页面、平台分支与公共浮层均已入表，后续逐页实现与 P6 逐页审查以本表为基准。
