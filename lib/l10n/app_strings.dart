/// Chinese strings — replaces the i18n AppLocalizations system.
/// All values sourced from app_zh.arb.
///
/// Usage: `AppStrings.xxx` or `final l10n = AppStrings.instance;`
class AppStrings {
  const AppStrings._();

  /// Singleton accessor for use with `l10n` variable shorthand.
  static const AppStrings instance = AppStrings._();

  // ── App ──
  static String get appTitle => 'Turna';

  // ── Common ──
  static String get commonCancel => '取消';
  static String get commonBack => '返回';
  static String get commonClose => '关闭';
  static String get commonDone => '完成';
  static String get commonRetry => '重试';
  static String get commonRefresh => '刷新';
  static String get commonSend => '发送';
  static String get commonApply => '应用';
  static String get commonPractice => '练习';
  static String get commonContinue => '继续';
  static String get commonGotIt => '知道了';
  static String get commonOk => '确定';
  static String get commonSave => '保存';
  static String get commonImport => '导入';
  static String get commonLater => '稍后';
  static String get commonNavLearn => '学习';
  static String get commonNavPlay => '练习';
  static String get commonNavProfile => '我的';
  static String get commonNavSettings => '设置';

  // ── Lesson ──
  static String get lessonCheck => '核对';
  static String get lessonChecked => '已核对';
  static String get lessonContinueUpper => '继续';
  static String get lessonGotItUpper => '知道了';

  // ── Settings ──
  static String get settingsCategoryAccount => '账户';
  static String get settingsCategoryAccountSubtitle => '资料、目标与统计';
  static String get settingsCategoryLearning => '学习';
  static String get settingsCategoryLearningSubtitle => '语言、语速、提醒与 Anki';
  static String get settingsCategoryAudioHaptics => '声音与触感';
  static String get settingsCategoryAudioHapticsSubtitle => '音效、振动与 TTS';
  static String get settingsCategoryAccessibility => '无障碍';
  static String get settingsCategoryAccessibilitySubtitle => '字号、对比度与主题';
  static String get settingsCategoryAiTools => 'AI 工具';
  static String get settingsCategoryAiToolsSubtitle => 'API、设计课程与教材导入';
  static String get settingsCategoryData => '数据';
  static String get settingsCategoryDataSubtitle => '导入、导出与重置';
  static String get settingsCategoryAbout => '关于';
  static String get settingsCategoryAboutSubtitle => '版本与开源许可';
  static String get settingsCategoryFunLab => '趣味实验室';
  static String get settingsCategoryFunLabSubtitle => '仅供娱乐的调试项';
  static String get settingsGroupMain => '常用';
  static String get settingsGroupDataAbout => '数据与关于';
  static String get settingsGroupLab => '实验室';
  static String get settingsTitle => '设置';
  static String get settingsLearningPrefsTitle => '学习偏好';
  static String get settingsAnkiSectionTitle => 'Anki 复习';
  static String get settingsAudioSectionTitle => '声音与触感';
  static String get settingsA11ySectionTitle => '阅读与感官';
  static String get settingsAppearanceSectionTitle => '外观';
  static String get settingsAiSectionTitle => 'AI 工具';
  static String get settingsDataSectionTitle => '数据管理';
  static String get settingsXiaoyiTitle => '用小艺解答题目';
  static String get settingsXiaoyiSubtitle =>
      '鸿蒙端：点击题目 AI 按钮直接拉起小艺，无需配置 API Key';
  static String get settingsBack => '返回';
  static String get settingsSoundEffectsTitle => '音效';
  static String get settingsSoundEffectsSubtitle => '为错误和升级播放音效';
  static String get settingsHapticFeedbackTitle => '触感反馈';
  static String get settingsHapticFeedbackSubtitle => '关键操作时振动';
  static String get settingsAutoRotateTitle => '自动旋转屏幕';
  static String get settingsAutoRotateSubtitle => '关闭时锁定竖屏；开启后跟随设备方向';
  static String get settingsAiApiConfigTitle => 'AI API 配置';
  static String get settingsAiApiConfigSubtitle => 'Base URL、API 密钥和模型（退出时不保存）';
  static String get settingsDesignCourseAiTitle => '用 AI 设计课程';
  static String get settingsDesignCourseAiSubtitle => '打开 AI 设计对话';
  static String get settingsImportTextbookTitle => '从教材导入';
  static String get settingsImportTextbookSubtitle => '将 Markdown/文本文件转换为课程章节';
  static String get settingsExportDataTitle => '导出数据';
  static String get settingsExportDataSubtitle => '将进度和/或课程内容保存到文件';
  static String get settingsImportDataTitle => '导入数据';
  static String get settingsImportDataSubtitle => '从导出文件恢复进度';
  static String get settingsClearMistakeLogTitle => '清除错题记录';
  static String get settingsClearMistakeLogSubtitle => '删除所有已保存的错题';
  static String get settingsResetProgressTitle => '重置课程进度';
  static String get settingsResetProgressSubtitle => '将所有课程标记为未完成';

  // ── Beginner guide ──
  static String get beginnerGuideTitle => '新手指南';
  static String get beginnerGuideEntry => '新手指南';
  static String get beginnerGuideEntrySubtitle => '了解核心功能与使用方法';
  static String get beginnerGuideIntro =>
      '欢迎来到 Turna！这里快速介绍应用的核心功能，点击任意功能卡即可跳转体验。';
  static String get beginnerGuideSectionLearn => '学习';
  static String get beginnerGuideSectionPractice => '练习与复习';
  static String get beginnerGuideSectionTools => '工具';
  static String get beginnerGuideSectionProfile => '我的';
  static String get beginnerGuideTryNow => '去体验';
  static String get beginnerGuideLearnTitle => '学习课程';
  static String get beginnerGuideLearnDesc =>
      '从问候语开始，按 CEFR 等级循序渐进地学习土耳其语词汇、表达与语法。';
  static String get beginnerGuideCourseMgmtTitle => '课程管理';
  static String get beginnerGuideCourseMgmtDesc => '切换、添加或重排所学语言课程。';
  static String get beginnerGuidePlayTitle => '练习中心';
  static String get beginnerGuidePlayDesc => '配对小游戏与每日挑战，轻松巩固所学。';
  static String get beginnerGuideSrsTitle => '间隔复习';
  static String get beginnerGuideSrsDesc => '基于 FSRS 算法的智能复习队列，让记忆更持久。';
  static String get beginnerGuideMistakesTitle => '错题本';
  static String get beginnerGuideMistakesDesc => '自动记录做错的题目，针对性重练薄弱点。';
  static String get beginnerGuideWeakWordsTitle => '弱词专项';
  static String get beginnerGuideWeakWordsDesc => '从近期错题生成 10 题小测，集中攻克易错词。';
  static String get beginnerGuideDictionaryTitle => '词典';
  static String get beginnerGuideDictionaryDesc => '搜索词汇、表达与语法点，点击播放发音。';
  static String get beginnerGuideAiTitle => 'AI 助手';
  static String get beginnerGuideAiDesc => '用 AI 设计课程、导入教材，或对错题进行深度讲解。';
  static String get beginnerGuideStatsTitle => '学习统计';
  static String get beginnerGuideStatsDesc => '查看每日 XP、学习时长与准确率趋势，追踪进度。';
  static String get settingsResetLearningDefaultsTitle => '重置为默认';
  static String get settingsResetLearningDefaultsSubtitle =>
      '恢复语速、提醒、小艺与 Anki 限额等学习偏好';
  static String get settingsResetLearningDefaultsDialogTitle => '重置学习设置为默认？';
  static String get settingsResetLearningDefaultsDialogMessage =>
      '将恢复语速、每日提醒、小艺提示和 Anki 每日限额等默认值。不会更改学习语言或课程进度。';
  static String get settingsResetLearningDefaultsConfirm => '重置';
  static String get settingsResetLearningDefaultsDone => '学习设置已恢复为默认';
  static String get settingsClearMistakeDialogTitle => '清除错题记录？';
  static String get settingsClearMistakeDialogMessage => '这将永久删除所有已保存的错题。';
  static String get settingsClearMistakeConfirm => '清除';
  static String get settingsMistakeLogCleared => '错题记录已清除';
  static String get settingsResetProgressDialogTitle => '重置课程进度？';
  static String get settingsResetProgressDialogMessage =>
      '所有课程完成记录和满分记录都将被清除。此操作无法撤销。';
  static String get settingsResetProgressConfirm => '重置';
  static String get settingsProgressReset => '课程进度已重置';
  static String get settingsImportDataDialogTitle => '导入数据？';
  static String get settingsImportDataDialogMessage =>
      '这将用文件内容覆盖当前进度。此操作无法撤销。建议先导出。';
  static String get settingsImportDataConfirm => '导入';
  static String get settingsCourseSavedRestart => '课程内容已保存；重启后生效';
  static String get settingsProgressRestoredRestart => '进度已恢复——重启应用以生效';
  static String get settingsNothingToImport => '无可导入内容';
  static String settingsImportFailed(Object error) => '导入失败：$error';
  static String settingsExportFailed(Object error) => '导出失败：$error';
  static String get settingsAiApiConfigSheetTitle => 'AI API 配置';
  static String get settingsAiApiConfigNotSaved => '密钥保存在本设备，重启后仍保留。';
  static String get settingsBaseUrlLabel => 'Base URL';
  static String get settingsBaseUrlHint => 'https://api.deepseek.com';
  static String get settingsApiKeyLabel => 'API 密钥';
  static String get settingsApiKeyHint => 'sk-...';
  static String get settingsModelLabel => '模型';
  static String get settingsModelHint => 'deepseek-v4-flash';
  static String get settingsSaveConfig => '保存配置';
  static String get settingsExportSheetTitle => '导出数据';
  static String get settingsExportSubtitle => '选择导出文件中包含的内容。';
  static String get settingsExportProgressTitle => '进度数据';
  static String get settingsExportProgressSubtitle => 'SRS、得分、连续学习天数、错题、成就';
  static String get settingsExportCourseTitle => '课程内容';
  static String get settingsExportCourseSubtitle => '内置土耳其语课程 JSON 文件';
  static String get settingsExportButton => '导出';
  static String get settingsExporting => '导出中…';
  static String get settingsAboutTurna => '关于 Turna';
  static String get settingsOpenSourceLicenses => '开源许可证';
  static String settingsVersionFooter(String version) => '版本 $version';
  static String settingsVersionFooterWithBuild(String version, String build) =>
      '版本 $version ($build)';
  static String get settingsAccountLearnerFallback => '学习者';
  static String get settingsThemeLight => '浅色';
  static String get settingsThemeDark => '深色';
  static String get settingsThemeSystem => '跟随系统';
  static String get settingsLearningLanguageTitle => '学习语言';
  static String get settingsLearningLanguageSubtitle => '选择你正在学习的语言';
  static String get settingsTtsSpeedTitle => 'TTS 语速';
  static String get settingsTtsSpeedSubtitle => '调整语音播放速度';
  static String settingsTtsSpeedValue(String ttsSpeed) => '${ttsSpeed}x';
  static String get settingsDailyReminderTitle => '每日提醒';
  static String get settingsDailyReminderSubtitle => '温和地提醒复习——无连续天数惩罚';
  static String get settingsSrsRetentionTitle => '复习目标保留率';
  static String settingsSrsRetentionValue(int percent) => '$percent%';
  static String get settingsSrsWeightsTitle => '记忆曲线权重';
  static String get settingsSrsWeightsDefault => '使用默认权重';
  static String settingsSrsWeightsCustom(int reviews) =>
      '已个性化（基于 $reviews 次复习）';
  static String get settingsSrsOptimize => '根据学习记录优化';
  static String get settingsSrsOptimizeHint =>
      '用本机复习历史微调 FSRS（需至少 300 次复习）。不会增加评分档。';
  static String get settingsSrsOptimizeNeedMore => '复习记录不足 300 次，暂无法优化';
  static String get settingsSrsOptimizeAccepted => '已应用个性化权重';
  static String get settingsSrsOptimizeRejected => '优化未带来稳定提升，仍使用原权重';
  static String get settingsSrsResetWeights => '恢复默认权重';
  static String get settingsSrsOptimizing => '正在优化…';
  static String srsPreviewFailMinutes(int minutes) => '约 $minutes 分钟';
  static String get srsPreviewTomorrow => '明天';

  static String get settingsReminderTimeTitle => '提醒时间';
  static String settingsReminderTimeSubtitle(String timeLabel) =>
      '当前 $timeLabel';
  static String get settingsTtsChecking => '正在检查设备 TTS 引擎…';
  static String settingsTtsReady(String locale) =>
      'Google TTS 就绪（$locale）——推荐用于学习';
  static String get settingsTtsGoogleInstalledMissingVoice =>
      'Google 已安装——请在系统 TTS 设置中下载土耳其语语音数据';
  static String get settingsTtsTurkishVoiceMissing => '土耳其语语音未就绪——打开系统 TTS 设置';
  static String settingsTtsGoogleMissing(Object oem) =>
      '未检测到 Google TTS（引擎：$oem）';
  static String get settingsVoiceSourceTitle => '语音来源';
  static String get settingsSystemTts => '系统 TTS';
  static String get settingsVoiceSourceDialogTitle => '语音来源';
  static String get settingsPlaySample => '播放示例（Merhaba）…';
  static String get settingsOpenSystemTts => '打开系统 TTS 设置…';
  static String get settingsInstallGoogleTts => '安装/打开 Google TTS…';
  static String settingsTtsNoVoicePlayed(Object error) => '未播放语音。$error';
  static String get settingsTtsNoVoicePlayedFallback =>
      '未播放语音。请检查 logcat 中的 TTS 错误。';
  static String settingsTtsPlaying(String userLabel) => '正在播放：$userLabel';
  static String get settingsTextSizeTitle => '文字大小';
  static String get settingsTextSizeSubtitle => '全局放大文字';
  static String settingsTextSizeValue(int textScale) => '${textScale}%';
  static String get settingsReduceMotionTitle => '减弱动态效果';
  static String get settingsReduceMotionSubtitle => '缩短或禁用动画与过渡';
  static String get settingsHighContrastTitle => '高对比度';
  static String get settingsHighContrastSubtitle => '使用高对比度主题';
  static String get settingsDyslexiaFontTitle => '阅读障碍友好字体';
  static String get settingsDyslexiaFontSubtitle => '切换到 Lexend 字体以便于阅读';
  static String get settingsSensoryReduceTitle => '减少感官刺激';
  static String get settingsSensoryReduceSubtitle => '静音非必要声音和触感';
  static String get settingsFocusModeTitle => '专注模式';
  static String get settingsFocusModeSubtitle => '隐藏主屏幕的轮播欢迎动画';
  static String get settingsUiLanguageTitle => '应用语言';
  static String get settingsUiLanguageSubtitle => '选择界面语言';
  static String get settingsUiLanguageSystem => '跟随系统';

  // ── Account Settings ──
  static String get accountEditName => '编辑昵称';
  static String get accountEditNameHint => '输入你的昵称';
  static String get accountEditNameTitle => '修改昵称';
  static String get accountEditNameSave => '保存';
  static String get accountBioHint => '添加一句学习座右铭…';
  static String get accountEditBioTitle => '编辑座右铭';
  static String get accountEditBioSave => '保存';
  static String get accountAvatarTitle => '选择头像颜色';
  static String get accountGoalsTitle => '学习目标';
  static String get accountDailyXpGoal => '每日经验目标';
  static String get accountDailyStudyGoal => '每日学习时长';
  static String get accountDailyLessonGoal => '每日完成课程';
  static String accountDailyStudyGoalValue(int minutes) => '$minutes 分钟';
  static String get accountStatsTitle => '学习统计';
  static String get accountStreak => '连续学习';
  static String accountStreakValue(int streak) => '$streak 天';
  static String get accountLessonsCompleted => '已完成课程';
  static String accountLessonsCompletedValue(int count) => '$count 课';
  static String get accountPerfectLessons => '满分课程';
  static String accountPerfectLessonsValue(int count) => '$count 课';
  static String get accountDataManagement => '管理数据';
  static String get accountDataManagementSubtitle => '导入、导出、清除数据';
  static String get accountResetTitle => '重置账户';
  static String get accountResetSubtitle => '清除所有学习数据并重新开始';
  static String get accountResetDialogTitle => '重置账户？';
  static String get accountResetDialogMessage =>
      '所有学习进度、SRS 数据、错题记录和成就都将被清除。此操作无法撤销。强烈建议先导出数据。';
  static String get accountResetConfirm => '重置';
  static String get accountResetDone => '账户已重置';

  // ── About ──
  static String get aboutTitle => '关于 Turna';
  static String get aboutWhatIsTitle => '什么是 Turna';
  static String get aboutWhatIsBody =>
      'Turna 是一款免费、开源的语言学习应用，专注于帮助你一步步建立真实的词汇和语法能力。它让学习保持离线、无干扰，并由你掌控。';
  static String get aboutHighlightsTitle => '亮点';
  static String get aboutHighlightOfflineTitle => '离线优先';
  static String get aboutHighlightOfflineSubtitle => '随时随地学习';
  static String get aboutHighlightSrsTitle => '间隔复习';
  static String get aboutHighlightSrsSubtitle => '记住更多';
  static String get aboutHighlightInteractionsTitle => '11 种交互';
  static String get aboutHighlightInteractionsSubtitle => '练习所有技能';
  static String get aboutPrivacyTitle => '隐私与本地优先';
  static String get aboutPrivacyBody =>
      '你学习的一切都保留在本设备上。Turna 没有云端后端、没有账户、没有追踪——你的进度、错题和设置永不离开手机。卸载应用会删除所有数据。唯一的网络访问是可选的（打开外部链接或你自己配置的 AI 工具）。';
  static String get aboutVersionTitle => '版本与更新日志';
  static String get aboutLinksTitle => '链接';
  static String get aboutUpstreamTitle => '上游项目';
  static String get aboutUpstreamSubtitle => 'github.com/rshrc/Varnamala';
  static String get aboutReportIssueTitle => '报告问题';
  static String get aboutReportIssueSubtitle => 'GitHub Issues';
  static String get aboutViewReleasesTitle => '查看发布';
  static String get aboutViewReleasesSubtitle => '更新日志与下载';
  static String get aboutShareTitle => '分享 Turna';
  static String get aboutCreditsTitle => '致谢';
  static String get aboutCreditsOriginal =>
      '原始框架由 Rishi Banerjee 和 Varnamala 开源社区构建。';
  static String get aboutCreditsFork => '本构建是一个本地优先的分叉版本，增加了无障碍设置和课程创作工具。';
  static String get aboutLicense => '基于 GNU 通用公共许可证 v3.0 授权。';
  static String aboutCopyright(String year) => '© $year Turna';
  static String get aboutBrandName => 'Turna';
  static String get aboutTagline => '学习语言，一步步来。';
  static String aboutVersionLabel(String version) => '版本 $version';
  static String aboutVersionWithBuild(String version, String buildNumber) =>
      '版本 $version（$buildNumber）';
  static String get aboutShareText =>
      '看看 Turna——一款免费、开源的语言学习应用！https://github.com/rshrc/Varnamala';
  static String aboutVersionShort(String version) => '版本 $version';
  static String aboutVersionBuild(String buildNumber) => '（$buildNumber）';
  static String get aboutHideChangelog => '隐藏';
  static String get aboutShowChangelog => '显示更新日志';
  static String get aboutOpenChangelog => '查看完整更新日志';
  static String get aboutOpenChangelogSubtitle => '版本里程碑与功能摘要';
  static String get aboutReleasesNote => '完整的发布历史，请查看 GitHub 发布页面。';
  static String get aboutMilestone1Title => 'future4 框架';
  static String get aboutMilestone1Body =>
      '完成整洁架构框架：依赖注入整合、音频/内容解耦、SRS 队列基类、GameProvider 外观模式、集成测试、发布流水线。';
  static String get aboutMilestone2Title => '斯瓦希里语 → 土耳其语转向';
  static String get aboutMilestone2Body =>
      '将目标语言迁移到土耳其语，并在第 1 章填充了真实的问候语课程（8 个单词 + 2 个表达）。';
  static String get aboutMilestone3Title => '无障碍设置';
  static String get aboutMilestone3Body =>
      '添加了神经多样性友好选项：文字大小、减弱动态效果、高对比度、阅读障碍友好字体、感官减弱、专注模式。';

  // ── Changelog ──
  static String get changelogTitle => '更新日志';
  static String get changelogIntro =>
      '以下为 Turna 主要版本与功能里程碑，条目为简要摘要，便于快速了解近期改动。';
  static String get changelogFooterNote =>
      '更详细的工程说明见仓库 docs/decisions/ 与 README。';
  static String get changelogCopyTooltip => '复制当前页内容';
  static String get changelogCopied => '已复制到剪贴板';
  static String get changeloadFallback => '无法读取 assets/changelog.md，已切换到内置版本';

  // ── About tabs ──
  static String get aboutTabAbout => '关于';
  static String get aboutTabChangelog => '更新日志';
  static String get aboutTabQuickStart => '使用指南';

  // ── Quick Start ──
  static String get quickStartLoadFallback => '无法读取 assets/quick_start.md';

  // ── Home ──
  static String get homeAiCourseDesigner => 'AI 课程设计器';
  static String get homeNewCourse => '新建课程';
  static String get homeNewCourseSheetTitle => '新建课程';
  static String get homeDesignWithAi => '用 AI 设计';
  static String get homeDesignWithAiSubtitle => '描述一门课程，让 AI 构建';
  static String get homeImportFromTextbook => '从教材导入';
  static String get homeImportFromTextbookSubtitle => '将 Markdown/文本文件转换为章节';
  static String get homeFromAnki => '从 Anki';
  static String get homeFromAnkiSubtitle => '导入 .apkg/.colpkg 牌组作为课程';
  static String get homeSampleAnki => '试用示例 Anki';
  static String get homeSampleAnkiSubtitle => '导入内置土耳其语问候示例牌组';
  static String get homeStreakBrokenTitle => '连续学习中断了';
  static String get homeStreakBroken => '你的连续天数已归零。今天学一点，重新开始吧。';

  static String get homeNewCourseComingSoon => '多语言课程功能即将推出。目前仅支持土耳其语课程。';
  static String get homeNewCourseUseAi => '你也可以使用 AI 课程设计器来创建自定义课程。';
  static String get dialogClose => '关闭';

  // ── Course management ──
  static String get courseManagementTitle => '课程管理';
  static String get courseManagementCurrentBadge => '当前';
  static String get courseManagementDefaultBadge => '默认';
  static String get courseManagementBuiltinSubtitle => '默认课程，不可删除';
  static String get courseManagementAddTitle => '添加课程';

  // Per-course smart-TTS settings (course management page).
  static String get courseTtsSettingsTitle => '朗读设置';
  static String get courseTtsAutoReadTitle => '点击自动朗读';
  static String get courseTtsAutoReadSubtitle => '点击选项或翻开卡片时自动朗读';
  static String get courseTtsNativeLangTitle => '翻译/母语语言';
  static String get courseTtsNativeLangSubtitle => '纯拉丁字母文本的朗读语音（如英语译文）';

  // ── Play ──
  static String get playQuickPlayTitle => '快速练习';
  static String get playQuickPlaySubtitle => '尽快匹配单词';
  static String get playMistakeReviewTitle => '错题复习';
  static String playMistakeReviewSubtitleWithCount(int mistakesCount) =>
      '$mistakesCount 个错题——最多练习 10 个';
  static String get playMistakeReviewSubtitleEmpty => '暂无错题记录';
  static String get playReviewTitle => '复习';
  static String playReviewSubtitleWithDue(int srsDue) => '$srsDue 个单词待复习';
  static String get playReviewSubtitleEmpty => '暂无待复习单词';
  static String get playGrammarReviewTitle => '语法复习';
  static String playGrammarReviewSubtitleWithDue(int grammarDue) =>
      '$grammarDue 个语法点待复习';
  static String get playGrammarReviewSubtitleEmpty => '暂无待复习语法';
  static String get playDailyChallengeTitle => '每日挑战';
  static String get playDailyChallengeSubtitle => '随机 15 题——测试你的土耳其语';
  static String get playWeakWordsTitle => '薄弱单词';
  static String playWeakWordsSubtitleWithCount(int weakCount) =>
      '$weakCount 个单词在过去 30 天内错过两次';
  static String get playWeakWordsSubtitleEmpty => '暂无薄弱单词';
  static String get playAnkiReviewTitle => 'Anki 复习';
  static String get playAnkiReviewSubtitle => '复习导入的 Anki 牌组';
  static String get playDictionaryTitle => '词典';
  static String get playDictionarySubtitle => '搜索单词、短语和语法';
  static String get playTodayFocusTitle => '今日重点';
  static String get playReviewCenterTitle => '复习中心';
  static String get playToolsTitle => '工具';
  static String get playStartAction => '开始';
  static String get playAiAssistantTitle => 'AI 助手';
  static String get playAiEngineReady => '引擎就绪';
  static String get playAiEngineNotConfigured => '未配置';
  static String get playAiViewAll => '全部 AI 功能';
  static String playMistakeFocusCount(int mistakesCount) =>
      '$mistakesCount 个错题';
  static String get playMistakeFocusEmpty => '暂无错题';
  static String playReviewFocusCount(int srsDue) => '$srsDue 个待复习';
  static String get playReviewFocusEmpty => '暂无待复习';
  static String get playDailyChallengeFocusCount => '随机 15 题';
  static String get playTitle => '练习';
  static String get playMatchMadness => '匹配狂热';
  static String playXpLabel(int sessionScore) => '$sessionScore XP';
  static String playRoundLabel(int roundsCompleted) => '第 $roundsCompleted 轮';
  static String get playInfiniteRoundsNote => '无限轮次。每次完美完成板后出现新单词。';
  static String get playRoundComplete => '本轮完成！正在加载新单词…';
  static String playTimeUp(int roundsCompleted, int score) =>
      '时间到！你完成了 $roundsCompleted 轮，获得 $score XP。';
  static String get playPlayAgain => '再玩一次';
  static String get playBrilliantRun => '精彩发挥！';
  static String get playChampionEnergy => '冠军之能！';
  static String get playLightningFast => '闪电速度！';
  static String playMatchCount(int matchedCount, int totalCount) =>
      '$matchedCount / $totalCount';
  static String get playDailyClose => '关闭';
  static String get playDailyTitle => '每日挑战';
  static String playDailyQuestion(int current, int total) =>
      '第 $current 题，共 $total 题';
  static String get playDailyChallengeFallback => '每日挑战';
  static String get playDailyContinue => '继续';
  static String get playDailyGotIt => '知道了';
  static String get playDailyNoQuestions => '暂无挑战题目';
  static String get playDailyCompleteFewLessons => '先完成几节课以充实题库。';
  static String get playWeakWordsEmpty =>
      '继续练习——暂无薄弱单词。\n过去 30 天内错过两次的单词会出现在这里。';
  static String get playWeakWordsTitleAppBar => '薄弱单词';

  // ── Review ──
  static String get reviewContinueUpper => '继续';
  static String get reviewGotItUpper => '知道了';
  static String get reviewWeakWordsTitleAppBar => '薄弱单词';
  static String get reviewDoYouKnow => '你认识这个单词吗？';
  static String get reviewDontKnow => '不认识';
  static String get reviewKnowIt => '认识';
  static String get reviewAgain => '重来';
  static String get reviewHard => '困难';
  static String get reviewGood => '良好';
  static String get reviewEasy => '简单';
  static String get reviewEmptyTitle => '复习';
  static String get reviewEmptyMessage => '你已经全部复习完了。';
  static String get reviewDueMessage => '个单词已到期——下拉刷新';
  static String get reviewNoItemsDue => '暂无待复习项';
  static String reviewDueCountMessage(int dueCount, String dueMessage) =>
      '$dueCount $dueMessage';
  static String get reviewCompletionTitle => '本轮完成！';
  static String get reviewCompletionMessage => '你已复习全部内容。';
  static String get reviewReviewAppBarTitle => '复习';
  static String reviewXpEarned(int xpEarned) => '+$xpEarned XP';
  static String reviewGemsEarned(int gemsEarned) => '+$gemsEarned 宝石';
  static String get reviewReviewMore => '继续复习';
  static String get reviewSrsTitle => '复习';
  static String get reviewSrsSessionComplete => '本轮完成！';
  static String reviewSrsCompletionMessage(int sessionCount) =>
      '你复习了 $sessionCount 项。';
  static String get reviewSrsAppBarTitle => '复习';
  static String reviewSrsTtsSpeed(String ttsSpeed) => '$ttsSpeed x';
  static String get reviewSrsTtsSpeedTooltip => 'TTS 语速';
  static String reviewSrsProgress(int currentIndex, int queueLength) =>
      '$currentIndex / $queueLength';
  static String get reviewSrsShowAnswer => '显示答案';
  static String get reviewSrsPlayPronunciation => '播放发音';
  static String get reviewSrsTapToReveal => '点击显示含义';
  static String reviewSrsLearnedIn(String lessonName) => '所学课程：$lessonName';
  static String reviewSrsFirstSeen(String wordId) => '首次出现：$wordId';
  static String get reviewSrsEntryNotFound => '未找到条目';
  static String reviewSrsPronunciation(String pronunciation) =>
      '/$pronunciation/';
  static String get reviewMistakeReviewTitle => '错题复习';
  static String get reviewViewMistakeList => '查看错题列表';
  static String get reviewNoMistakes => '暂无错题可复习。\n错题会自动记录在此处；每次最多练习 10 个。';
  static String get reviewMyMistakesTitle => '我的错题';
  static String get reviewNoMistakesRecorded => '暂无错题记录';
  static String get reviewKeepItUp => '继续保持！';
  static String get reviewMistakesLabel => '错题';
  static String get reviewWordsLabel => '单词';
  static String get reviewGrammarLabel => '语法';
  static String get reviewUnknownQuestion => '未知问题';
  static String get reviewReviewGrammar => '复习语法';
  static String get reviewGotItNow => '现在我会了';
  static String get reviewYourAnswer => '你的答案';
  static String get reviewCorrectAnswer => '正确答案';
  static String get reviewDash => '—';
  static String reviewGrammarChip(String title) => '语法：$title';
  static String get reviewPracticeTitle => '练习';
  static String get reviewCannotPractice => '此错题无法练习。';
  static String get reviewPracticeMistakeTitle => '错题练习';
  static String get reviewGrammarReviewTitle => '语法复习';
  static String get reviewGrammarEmptyMessage => '你已经全部复习完了。';
  static String get reviewGrammarDueMessage => '个语法点已到期——刷新以加载';
  static String get reviewGrammarSessionComplete => '本轮完成！';
  static String reviewGrammarCompletionMessage(int sessionCount) =>
      '你复习了 $sessionCount 个语法点。';
  static String get reviewGrammarAppBarTitle => '语法复习';
  static String reviewGrammarProgress(int currentIndex, int queueLength) =>
      '$currentIndex / $queueLength';
  static String reviewGrammarPracticeLabel(
          int practiceIndex, int practiceLength) =>
      '练习 $practiceIndex / $practiceLength';
  static String get reviewGrammarDoYouUnderstand => '你理解这个语法点吗？';
  static String get reviewGrammarNextPractice => '下一个练习';
  static String get reviewGrammarRateGrammar => '为这个语法点评分';
  static String get reviewGrammarShowExplanation => '显示解释';
  static String reviewGrammarLearnedIn(String lessonName) => '所学课程：$lessonName';
  static String reviewGrammarFirstSeen(String wordId) => '首次出现：$wordId';
  static String get reviewGrammarTapToReveal => '点击显示解释';
  static String get reviewGrammarPointNotFound => '未找到语法点';

  // ── Lesson Details ──
  static String get lessonFlipCardCaption => '翻牌';
  static String get lessonShowAnswer => '显示答案';
  static String get lessonTapToReveal => '点击卡片查看答案';
  static String get lessonTapToReturnFront => '点击卡片返回正面';
  static String get lessonHowWellDidYouKnow => '你对这个有多熟悉？';
  static String get lessonPlayAudioLabel => '播放音频';
  static String get lessonAudioMissing => '音频文件缺失';
  static String get lessonAudioPlaybackFailed => '音频播放失败';
  static String get lessonSpeakLabel => '朗读';
  static String get lessonFillBlankCaption => '填空';
  static String get lessonFillBlankHint => '___';
  static String get lessonCorrectAnswer => '正确答案';
  static String get lessonListenAndPickCaption => '听音选择';
  static String get lessonSummaryCaption => '概要';
  static String get lessonListenToSummary => '收听概要';
  static String get lessonTapToReplay => '点击喇叭重播';
  static String get lessonTapToListen => '点击喇叭收听';

  /// Single-answer MCQ caption (was misleadingly "多项选择").
  static String get lessonMultipleChoiceCaption => '单选题';
  static String get lessonSelectAllCaption => '多选题（请选择所有正确项）';
  static String lessonSelectAtLeast(int min, int count) =>
      '至少选择 $min 项（已选 $count 项）';
  static String lessonSelectExact(int min, int count) =>
      '选择 $min 项（已选 $count 项）';
  static String lessonSelectRange(int min, int max, int count) =>
      '选择 $min–$max 项（已选 $count 项）';
  static String get lessonReadingComprehensionCaption => '阅读理解';
  static String get lessonShortAnswerCaption => '简答题';
  static String get lessonTypeYourAnswer => '输入你的答案…';
  static String get lessonTrueFalseCaption => '判断题';
  static String get lessonTrue => '正确';
  static String get lessonFalse => '错误';
  static String get lessonArrangeWordsCaption => '排列单词';
  static String get lessonTapRightOrder => '按正确顺序点击单词';
  static String get lessonWordBank => '词库';
  static String get lessonCorrectOrder => '正确顺序';
  static String get lessonTapWordToStart => '点击下方单词开始';
  static String lessonSpeakTerm(String term) => '朗读 $term';
  static String get lessonSpeakContextSentence => '朗读例句';
  static String get lessonTapToContinue => '点击继续';
  static String get lessonItemNotLoaded => '此项无法加载。';
  static String get lessonTranslateCaption => '翻译此句';
  static String get lessonTypeTranslation => '输入译文…';
  static String get lessonCorrectTranslation => '正确译文';
  static String get lessonTypeWhatYouHearCaption => '听写';
  static String get lessonTypeHere => '在此输入…';
  static String get lessonCompleteTitle1 => '课程完成！';
  static String get lessonCompleteSubtitle1 => '出色的专注。你完成了本课。';
  static String get lessonCompleteTitle2 => '真快！';
  static String get lessonCompleteSubtitle2 => '你上升得很快。保持连续学习。';
  static String get lessonCompleteTitle3 => '出色！';
  static String get lessonCompleteSubtitle3 => '每节课都让你更接近精通。';
  static String get lessonPerfectLesson => '完美！全部答对。';
  static String get lessonCorrect => '正确';
  static String get lessonWrong => '错误';
  static String get lessonTime => '用时';
  static String get lessonXp => '经验值';
  static String get lessonAnswerBreakdown => '答题明细';
  static String lessonResultsCount(int correctCount, int totalCount) =>
      '$correctCount / $totalCount';
  static String get lessonBackToCourses => '返回课程';
  static String get lessonAccuracy => '正确率';
  static String lessonPercentValue(int percent) => '${percent}%';
  static String lessonQuestionResult(int index, String prompt) =>
      '$index. $prompt';
  static String lessonQuestionAnswer(String correctAnswer) =>
      '答案：$correctAnswer';
  static String get lessonNotYet => '还未通过';
  static String lessonMasteryMessage(
          int correct, int total, int accuracyPercent) =>
      '你答对 $correct / $total（$accuracyPercent%）。需要 80% 才能通过。再试一次！';
  static String get lessonTryAgain => '再试一次';
  static String lessonDurationSeconds(int seconds) => '${seconds}秒';
  static String lessonDurationMinutes(int minutes, int seconds) =>
      '${minutes}分${seconds}秒';
  static String get lessonAiHelperTooltip => 'AI 课程助手';
  static String get lessonAiHintTooltip => 'AI 提示';
  static String get lessonNoContent => '无内容';
  static String get lessonLessonFallback => '课程';
  static String get lessonCouldNotLoadLesson => '无法加载课程';

  // ── AI ──
  static String get aiNotConfiguredTitle => 'AI 未配置';
  static String get aiNotConfiguredMessageLesson =>
      '在使用 AI 提示前，请在 设置 → 学习 → AI API 配置 中填写 Base URL / API 密钥 / 模型。';
  static String get aiGoToSettings => '前往设置';
  static String get aiCourseDesignerTitle => 'AI 课程设计器';
  static String get aiCourseParametersTooltip => '课程参数';
  static String get aiCourseParametersTitle => '课程参数';
  static String get aiTargetLanguageLabel => '目标语言';
  static String get aiSourceLanguageLabel => '源语言';
  static String get aiTopicLabel => '主题';
  static String get aiLevelLabel => '级别';
  static String get aiUnitsLabel => '单元数';
  static String get aiLessonsPerUnitLabel => '每单元课数';
  static String get aiTemplateLabel => '模板';
  static String get aiGenreBatchTitle => '体裁批量';
  static String get aiGenreBatchSubtitle => '使用 [genre] 标签进行多模板批量生成';
  static String get aiGroundedGenerationTitle => '基于已有内容生成';
  static String get aiGroundedGenerationSubtitle => '复用现有的词汇、表达和语法点';
  static String get aiExtraInstructionsLabel => '额外说明（可选）';
  static String get aiEmptyHintWish =>
      '告诉 AI 你想要什么课程。例如：\n「我想教土耳其语旅行用语——问候和点餐。」';
  static String aiErrorBubble(Object error) => '错误：$error';
  static String get aiCourseGenerated => '课程已生成';
  static String aiAiExplanation(String explanation) => 'AI 说明：$explanation';
  static String get aiSaveToCourseTree => '保存到课程树';
  static String get aiTypeIdea => '输入你的想法…';
  static String get aiSwipeToFinalize => '滑动以确认';
  static String get aiReleaseToFinalize => '释放以确认';
  static String get aiCourseSaved => '课程已保存到数据库。';
  static String aiSaveFailed(Object error) => '保存失败：$error';
  static String get aiTextbookImportTitle => '从教材导入';
  static String get aiTextbookNotConfiguredMessage =>
      '请先在 设置 → AI API 配置 中填写 Base URL / API 密钥 / 模型。';
  static String get aiTextbookTargetLanguageLabel => '目标语言';
  static String get aiTextbookSourceLanguageLabel => '源语言';
  static String get aiTextbookLevelLabel => '级别';
  static String get aiTextbookImportStrategyLabel => '导入策略';
  static String get aiTextbookPresetLabel => '教材类型';
  static String get aiTextbookPickPrompt => '选择一个 Markdown 或文本文件以作为课程章节导入。';
  static String get aiTextbookPickFile => '选择文件';
  static String aiTextbookSelected(String fileName) => '已选择：$fileName';
  static String get aiTextbookParsing => '正在解析文件…';
  static String get aiTextbookExtracting => '正在提取知识…';
  static String get aiTextbookReviewChapters => '审查章节';
  static String aiTextbookChapterChars(int length) => '$length 字符';
  static String get aiTextbookReviewKnowledge => '审查提取的知识';
  static String get aiTextbookReviewSearchHint => '搜索词条、表达或语法…';
  static String get aiTextbookTabWords => '词汇';
  static String get aiTextbookTabExpressions => '表达';
  static String get aiTextbookTabGrammar => '语法';
  static String get aiTextbookReviewEmpty => '暂无条目。可返回重新提取，或继续查看冲突预览。';
  static String get aiTextbookEditResource => '编辑条目';
  static String get aiTextbookPrimaryField => '正面 / 术语';
  static String get aiTextbookSecondaryField => '译文 / 说明';
  static String get aiTextbookDeleteResource => '删除';
  static String get aiTextbookContinueToConflict => '继续 · 冲突预览';
  static String get aiTextbookConflictTitle => '导入冲突预览';
  static String get aiTextbookConflictSubtitle => '确认后才会写入课程。跳过的章节不会导入。';
  static String aiTextbookCollisionNew(int n) => '新增 $n';
  static String aiTextbookCollisionDup(int n) => '重复 $n';
  static String get aiTextbookActionAppend => '新建';
  static String get aiTextbookActionMerge => '合并写入';
  static String get aiTextbookActionSkip => '跳过';
  static String get aiTextbookActionReplace => '替换';
  static String get aiTextbookActionAppendNew => '另存为新 ID';
  static String get aiTextbookConfirmImport => '确认导入';
  static String get aiTextbookBackToReview => '返回审校';
  static String get aiTextbookStrategyMerge => '合并（保留并更新）';
  static String get aiTextbookStrategySkip => '跳过已有';
  static String get aiTextbookStrategyReplace => '强制替换';
  static String get aiTextbookStrategyAppend => '另存为新条目';
  static String aiTextbookWords(int count) => '单词：$count';
  static String aiTextbookExpressions(int count) => '表达：$count';
  static String aiTextbookGrammar(int count) => '语法：$count';
  static String get aiTextbookImportComplete => '导入完成！';
  static String aiTextbookErrorFooter(Object error) => '错误：$error';
  static String get aiTextbookExtractKnowledge => '提取知识';
  static String get aiTextbookImportSections => '导入章节';
  static String get aiLessonHelperTitle => 'AI 课程助手';
  static String get aiLessonHelperHint => '例如「让这个更简单」或「添加 3 个练习」';
  static String get aiLessonHelperInstructionLabel => '指令';
  static String get aiLessonHelperChipMakeEasier => '降低难度';
  static String get aiLessonHelperChipMakeHarder => '提高难度';
  static String get aiLessonHelperChipAddExercises => '添加 3 个练习';
  static String get aiLessonHelperChipListening => '改为听力练习';
  static String get aiLessonHelperChipPolish => '优化提示词';
  static String aiLessonHelperError(Object error) => '出错了：$error';
  static String get aiLessonHelperErrorUnknown => '出错了：未知错误';
  static String get aiLessonHelperPreviewTitle => '预览';
  static String get aiLessonHelperTransformationReady => '转换已就绪。点击应用以更新课程。';
  static String get aiLessonHelperTransform => '转换';
  static String aiLessonHelperInvalidJson(Object error) => '无效的课程 JSON：$error';
  static String get aiLessonHelperLessonUpdated => '课程已更新。';
  static String aiLessonHelperUpdateFailed(Object error) => '更新失败：$error';
  static String get aiTutorTitle => 'AI 导师';
  static String aiTutorTitleWithType(String typeLabel) => 'AI 导师 · $typeLabel';
  static String get aiEmptyHintTutor => 'AI 正在为此问题准备解释…';
  static String get aiThinking => 'AI 正在思考…';
  static String get aiAskMore => '继续提问…';
  static String get aiHintTitle => 'AI 提示';
  static String aiHintTitleWithType(String typeLabel) => 'AI 提示 · $typeLabel';
  static String aiHintError(Object error) => '出错了：$error';
  static String get aiHintErrorUnknown => '出错了：未知错误';
  static String get aiHintOpenChat => '打开对话';

  // ── AI depth tutor ──
  static String get aiDepthTutorTitle => '深度讲解';
  static String get aiDepthTutorSubtitle => '选择一种方式深入理解这道题';
  static String get aiDepthGrammar => '语法讲解';
  static String get aiDepthSynonyms => '近义词辨析';
  static String get aiDepthDecompose => '句子拆解';
  static String get aiDepthWhyWrong => '为什么做错了';
  static String get aiDepthGrammarPointLabel => '语法点';
  static String get aiDepthSynonymWordsLabel => '要辨析的词（逗号分隔）';
  static String get aiDepthGenerate => '生成';
  static String get aiDepthCopy => '复制';
  static String get aiDepthCopied => '已复制';
  static String get aiDepthNeedAnswer => '需要先作答并核对才能讲解错因';
  static String aiDepthError(Object error) => '出错了：$error';
  static String get aiDepthRelatedExamples => '相关例句';
  static String get aiDepthContrastWith => '易混淆';
  static String get aiDepthNuance => '差异';
  static String get aiDepthWhenToUseA => '用 A 的场景';
  static String get aiDepthWhenToUseB => '用 B 的场景';
  static String get aiDepthStructure => '句型';
  static String get aiDepthWhyWrongLabel => '错在哪';
  static String get aiDepthProbablyThought => '你可能以为';
  static String get aiDepthHowToRemember => '如何记住';

  // ── AI tutor (Phase 2.2) ──
  static String get tutorLaunchTitle => 'AI 伴学';
  static String get tutorLaunchSubtitle => '让 AI 基于你的最近错题 / 弱词，生成一节定制化复习课。';
  static String get tutorLaunchByMistakesCta => '按本周错题定制';
  static String get tutorLaunchByWeakWordsCta => '针对弱词生成 10 题';
  static String get tutorLaunchByMistakesTitle => '本周错题复习';
  static String get tutorLaunchByWeakWordsTitle => '弱词专项';
  static String get tutorLaunchRun => '生成定制复习';
  static String get tutorLaunchIdleHint => '选择上面一个侧重，然后点生成。';
  static String get tutorLaunchGathering => '正在收集你的学习上下文...';
  static String get tutorLaunchPlanning => 'AI 正在定制复习小节...';
  static String get tutorLaunchSaving => '保存定制小节...';
  static String get tutorLaunchErrorUnknown => '生成失败，请稍后再试。';
  static String tutorLaunchSaved(String name) => '已生成：$name，跳转中...';

  // ── AI Hub (Phase 2.3) ──
  static String get commonNavAiHub => 'AI';
  static String get aiHubTitle => 'AI Hub';
  static String get aiHubHeroReconfigure => '重新配置';
  static String get aiHubHeroIncomplete => '请先填写 API Key + Base URL + 模型';
  static String get aiHubContinue => '继续';
  static String get aiHubContinueEmpty => '还没有 AI 任务，去生成一个吧';
  static String get aiHubNew => '开始新的';
  static String get aiHubStartWish => '设计课程（AI）';
  static String get aiHubStartTextbook => '导入教材';
  static String get aiHubStartTutorMistakes => '按错题复习';
  static String get aiHubStartTutorWeak => '弱词专项';
  static String get aiHubStartDepthTutor => '深度讲解当前题';
  static String get aiHubDepthTutorSubtitleOn => '基于当前题目深度讲解';
  static String get aiHubDepthTutorSubtitleOff => '请先在课程中打开一道题';
  static String get aiHubTools => '工具';
  static String get aiHubToolsTestConnection => '测试连接';
  static String aiHubToolsTestConnectionOk(int latencyMs) =>
      '连接成功（${latencyMs}ms）';
  static String get aiHubToolsTestConnectionFail => '连接失败';
  static String get aiHubToolsClearCache => '清缓存';
  static String get aiHubToolsCleared => '缓存已清空';
  static String get aiHubToolsViewApiConfig => '查看 API 配置';

  // ── AI config sheet (Phase 2.4) ──
  static String get aiHubFieldPreset => 'AI 服务商';
  static String get aiHubFieldBaseUrlHintPreset => '来自所选预设，不可编辑';
  static String get aiHubFieldModelChat => '聊天模型';
  static String get aiHubFieldModelJson => 'JSON 模型';
  static String get aiHubFieldStrictSchema => '严格 JSON 模式';
  static String get aiHubFieldCacheEnabled => '启用缓存';
  static String get aiHubFieldCacheEnabledHint => '关闭后每次都会重新请求模型';
  static String aiHubFieldCacheStats(
          int entries, int hits, int misses, int diskWrites) =>
      '缓存: $entries 条 / 命中 $hits / 未命中 $misses / 落盘 $diskWrites';

  // ── AI config sheet 分组标题 ──
  static String get aiConfigGroupConnection => '连接';
  static String get aiConfigGroupModels => '密钥与模型';
  static String get aiConfigGroupAdvanced => '高级';

  // ── AI config page (standalone) ──
  static String get aiConfigStatusConfigured => '已配置';
  static String get aiConfigStatusNotConfigured => '未配置';
  static String get aiConfigStatusHintIncomplete => '填写下方服务商与密钥即可启用 AI 功能';
  static String get aiConfigProviderSectionHint => '选择你的 AI 服务商';
  static String get aiConfigTestDisabledHint => '请先完成配置';
  static String get aiConfigCustomProviderLabel => '自定义';

  // ── Anki ──
  static String get ankiImportTitle => '导入 Anki 牌组';
  static String get ankiImportDialogTitle => '导入 Anki 牌组';
  static String get ankiImportSelectTitle => '导入 Anki 牌组';
  static String get ankiImportSelectSubtitle =>
      '选择从 Anki 导出的 .apkg 或 .colpkg 文件';
  static String get ankiChooseFile => '选择文件';
  static String get ankiParsing => '正在解析 Anki 集合…';
  static String get ankiCollectionSummary => '集合概要';
  static String get ankiDecksLabel => '牌组';
  static String get ankiNotesLabel => '笔记';
  static String get ankiCardsLabel => '卡片';
  static String get ankiMediaFilesLabel => '媒体文件';
  static String ankiImportSourceCards(int count) => '源卡片：$count';
  static String ankiImportStructuredCards(int count) => '结构化卡片：$count';
  static String ankiImportFidelityCards(int count) => 'HTML 保真卡片：$count';
  static String ankiImportUnknownTemplates(int count) => '未识别模板：$count';
  static String ankiImportSuspended(int count) => '暂停卡：$count';
  static String ankiImportBuried(int count) => '埋藏卡：$count';
  static String ankiImportMissingMedia(int count) => '缺失媒体：$count';
  static String get ankiImportSchedulingMigrated => '已包含调度信息';
  static String get ankiImportHistoryMigrated => '已包含复习历史';
  static String get ankiDeckStructure => '牌组结构';
  static String ankiDeckCardCount(int cardCount) => '$cardCount 张卡片';
  static String get ankiNotetypeMapping => '自动识别结果';
  static String get ankiMappingOverrideHint =>
      '点按可修改识别结果；同一笔记类型中的单选和多选会按每张卡的题面与答案分别判断。';
  static String get ankiAiIdentify => 'AI 智能识别';
  static String get ankiAiIdentifying => 'AI 识别中…';
  static String get ankiAiNotConfiguredMessage =>
      '未配置 AI，无法智能识别。请先在「设置 > AI 工具」中配置 AI API。';
  static String get ankiNotetypePreview => '样例卡预览';
  static String get ankiNotetypeFields => '字段';
  static String get ankiNotetypeSampleFront => '正面';
  static String get ankiNotetypeSampleBack => '背面';
  static String get ankiMappingTypeAnkiCard => '翻面卡';
  static String get ankiMappingTypeWordEntry => '词汇（可出单选）';
  static String get ankiMappingTypeExpression => '表达/句子';
  static String get ankiMappingTypeCloze => 'Cloze 填空';
  static String get ankiMappingTypeMultipleChoice => '单选题';
  static String get ankiMappingTypeMultiSelect => '多选题';
  static String get ankiMappingTypeAutoChoice => '选择题（逐卡自动识别单选/多选）';
  static String get ankiMappingTypeFillBlank => '填空题';
  static String get ankiMappingTypeTypeAnswer => '打字题';
  static String get ankiMappingTypeListenPick => '听力选择';
  static String get ankiMappingEditTitle => '编辑识别结果';
  static String get ankiMappingEditTooltip => '编辑识别结果';
  static String get ankiMappingFieldType => '卡片类型';
  static String get ankiMappingFieldFront => '正面字段';
  static String get ankiMappingFieldBack => '背面字段';
  static String get ankiMappingFieldsAutoHint => '该类型字段由系统逐卡自动识别，无需手动选择。';
  static String get ankiMappingResetAuto => '恢复自动识别';
  static String get ankiMappingReason => '识别依据';
  static String get ankiOrganizationTitle => '组织结构';
  static String get ankiDetectedUnits => '识别到的单元';
  static String get ankiDetectedLessons => '识别到的课时';
  static String get ankiResolvedCards => '含单元/课时标签的卡片';
  static String get ankiOrganizationNone => '未发现单元/课时标签';
  static String get ankiOrganizationNoneDesc => '卡片将按每课 20 张分组。';
  static String get ankiSmartGrouping => '智能分组';
  static String get ankiSmartGroupingDesc => '将标签和字段映射为命名的单元与课时';
  static String get ankiCollisionReport => '冲突报告';
  static String get ankiNewCards => '新卡片';
  static String get ankiExistingCards => '已存在';
  static String get ankiImportStrategy => '导入策略';
  static String get ankiImportLearningProgress => '导入 Anki 学习进度';
  static String get ankiImportLearningProgressOnDesc =>
      '保留原卡片的到期时间、间隔、次数、暂停状态和复习历史。';
  static String get ankiImportLearningProgressOffDesc =>
      '按新卡导入，不读取原排程与复习历史（推荐）。';
  static String ankiImportCountsVerified(
    int source,
    int stored,
    int indexed,
  ) =>
      '数量已核对：源卡 $source · 已存储 $stored · 已索引 $indexed';
  static String get ankiImportSchedulingReset => '学习进度：按新卡重置';
  static String get ankiImportComplete => '导入完成！';
  static String get ankiStartLearning => '立即学习';
  static String ankiCardsImported(int cardCount) => '已导入 $cardCount 张卡片';
  static String ankiLessonsCreated(int lessonCount) => '已创建 $lessonCount 节课';
  static String ankiVocabAdded(int wordEntryCount) =>
      '已添加 $wordEntryCount 个词汇条目';
  static String get ankiPickFileError => '请选择 .apkg 或 .colpkg 文件。';
  static String ankiPickFileFailed(Object error) => '选择文件失败：$error';
  static String ankiParseFailed(Object error) => '解析失败：$error';
  static String get ankiPreparingImport => '正在准备导入…';
  static String get ankiAssemblingCourse => '正在构建课程树…';
  static String get ankiMigratingSrs => '正在迁移 SRS 状态…';
  static String get ankiCopyingMedia => '正在复制媒体文件…';
  static String get ankiSavingMetadata => '正在保存导入元数据…';
  static String ankiImportFailed(Object error) => '导入失败：$error';
  // Fallback file-import flows used when the system FilePicker is unavailable
  // (e.g. trimmed emulator ROMs without the pickersheet bundle).
  static String get ankiFallbackScanTitle => '从已下载文件中选择';
  static String get ankiFallbackScanSubtitle => '扫描应用可见的目录（例如下载目录、缓存目录）';
  static String get ankiFallbackScanEmpty => '未在已知目录找到 .apkg / .colpkg 文件。';
  static String get ankiFallbackScanFailed => '扫描失败：';
  static String get ankiFallbackPathTitle => '输入文件路径';
  static String get ankiFallbackPathSubtitle => '从文件管理器复制完整路径后粘贴进来';
  static String get ankiFallbackPathHint => '例如：/storage/.../deck.apkg';
  static String get ankiFallbackPathAction => '导入此文件';
  static String get ankiFallbackNoResult => '未找到匹配的文件';
  static String get ankiFallbackPickFileFirst => '系统文件选择器不可用，请尝试其他方式：';
  static String get ankiStrategyMerge => '合并';
  static String get ankiStrategySkipExisting => '跳过已存在';
  static String get ankiStrategyForceReplace => '强制替换';
  static String get ankiStrategyAppendAsNew => '追加为新';
  static String get ankiStrategyMergeDesc => '更新已存在卡片，添加新卡片';
  static String get ankiStrategySkipExistingDesc => '仅导入不存在的卡片';
  static String get ankiStrategyForceReplaceDesc => '替换所有已存在数据';
  static String get ankiStrategyAppendAsNewDesc => '全部作为新卡片添加（加后缀）';
  static String get ankiReviewTitle => 'Anki 复习';
  static String get ankiNoCardsDue => '暂无待复习的 Anki 卡片。';
  static String get ankiReviewPreparing => '正在准备本批卡片…';
  static String get ankiReviewLoadFailed => '加载复习卡片失败';
  static String ankiReviewLoadFailedDetail(Object error) => '加载失败：$error';
  static String get ankiReviewRetry => '重试';
  static String get ankiReviewScreenTitle => 'Anki 复习';
  static String get ankiImportNewDeck => '导入新牌组';
  static String ankiCardsDueReview(int totalDue) => '$totalDue 张卡片待复习';
  static String get ankiReviewAll => '全部复习';
  static String get ankiNoDecksTitle => '未导入 Anki 牌组';
  static String get ankiNoDecksSubtitle => '导入 .apkg 文件以开始复习';
  static String get ankiImportDeck => '导入牌组';
  static String ankiQuotaRemaining(int newLeft, int reviewLeft) =>
      '今日剩余：新卡 $newLeft 张，复习 $reviewLeft 张';
  static String get ankiQuotaExhausted => '已达今日上限 — 明天再来';
  static String get ankiUninstallDeck => '移除牌组';
  static String get ankiUninstallConfirmTitle => '移除此牌组？';
  static String get ankiUninstallConfirmBody => '将删除该牌组的卡片、复习进度和媒体文件，此操作无法撤销。';
  static String get ankiDeckRemoved => '牌组已移除';

  // ── Courses ──
  static String get coursesCouldNotLoadCourse => '无法加载课程';
  static String get coursesNoSectionsFound => '未找到课程章节。';
  static String get coursesCouldNotLoadSection => '无法加载章节';
  static String get coursesNoUnitsAvailable => '暂无可用单元';
  static String get coursesLoadingCourses => '正在加载课程…';
  static String get coursesLessonTypeNormal => '课程';
  static String get coursesLessonTypeListening => '听力';
  static String get coursesLessonTypeReading => '阅读';
  static String get coursesLessonTypeReview => '复习';
  static String get coursesLessonTypeChallenge => '挑战';
  static String get coursesPerfect => '完美';
  static String coursesUnitProgress(int completedCount, int lessonsCount) =>
      '$completedCount/$lessonsCount';
  static String get coursesChooseSection => '选择章节';

  // ── Dictionary ──
  static String get dictionaryTitle => '词典';
  static String get dictionarySearchHint => '搜索土耳其语或中文…';
  static String get dictionarySearchEmpty => '搜索单词、短语和语法';
  static String get dictionaryNoMatches => '无匹配结果';
  static String get dictionaryKindWord => '单词';
  static String get dictionaryKindPhrase => '短语';
  static String get dictionaryKindGrammar => '语法';
  static String get dictionaryPlayPronunciation => '播放发音';

  // ── Onboarding ──
  static String get onboardingReclaimingTitle => '重拾语言学习';
  static String get onboardingBody =>
      '还记得学习是为了知识，而不是最大化广告收入吗？没有生命值，没有体力，没有付费取胜。纯粹的开源教育。';
  static String get onboardingStartLearning => '开始学习';

  // ── Profile ──
  static String get profileTitle => '我的';
  static String get profileShare => '分享';
  static String get profileShareYourProgress => '分享你的进度';
  static String get profileShareButton => '分享';
  static String get profileSharing => '分享中…';
  static String profileShareFailed(Object error) => '无法分享进度：$error';
  static String get profileLearnerFallback => '学习者';
  static String get profileAchievementsTitle => '成就';
  static String profileViewMore(int remainingCount) => '查看另外 $remainingCount 项';
  static String get profileShowLess => '收起';
  static String profileAchievementLevel(int level) => 'Lv.$level';
  static String profileAchievementProgress(int current, int displayTarget) =>
      '$current/$displayTarget';
  static String get profileLearningStatsTitle => '学习统计';
  static String get profileXpToday => '今日经验';
  static String get profileStudyTime => '学习时长';
  static String get profileAccuracy => '正确率';
  static String profileStudyTimeValue(int minutes) => '${minutes}分';
  static String profileAccuracyValue(int accuracy) => '${accuracy}%';
  static String get profileLast7Days => '最近 7 天';
  static String get profileTotalStudyTime => '总学习时长';
  static String get profileOverallAccuracy => '总正确率';
  static String get profileLessonsDone => '完成课程';
  static String get profileReviewsDone => '复习次数';
  // ── Review progress ──
  static String get reviewProgressTitle => '复习进度';
  static String get reviewProgressSubtitle => '分源统计、筛选与记忆曲线';
  static String get reviewProgressSourceAll => '全部';
  static String get reviewProgressSourceCourse => '课程 · 土耳其语';
  static String get reviewProgressSourceGrammar => '语法';
  static String reviewProgressSourceAnki(String id) {
    final short = id.length > 8 ? id.substring(0, 8) : id;
    return 'Anki · $short';
  }

  static String reviewProgressSourceAnkiNamed(String name) => 'Anki · $name';
  static String get reviewProgressFilterType => '类型';
  static String get reviewProgressFilterMaturity => '阶段';
  static String get reviewProgressFilterDue => '到期';
  static String get reviewProgressFilterRange => '曲线时段';
  static String get reviewProgressTypeAll => '全部';
  static String get reviewProgressTypeWord => '单词';
  static String get reviewProgressTypeExpression => '表达';
  static String get reviewProgressTypeGrammar => '语法';
  static String get reviewProgressDueAny => '不限';
  static String get reviewProgressDueOverdue => '已到期';
  static String get reviewProgressDue7 => '7 日内';
  static String get reviewProgressDue30 => '30 日内';
  static String get reviewProgressRangeAll => '全部时间';
  static String get reviewProgressRange7 => '近 7 天';
  static String get reviewProgressRange30 => '近 30 天';
  static String get reviewProgressRange90 => '近 90 天';
  static String get reviewProgressKpiRetention => '保留率';
  static String get reviewProgressKpiMastery => '掌握度';
  static String get reviewProgressKpiCards => '卡片';
  static String get reviewProgressKpiReviews => '复习次数';
  static String get reviewProgressSourcesTitle => '分源进度';
  static String get reviewProgressEmpty => '暂无复习卡片。去学一课或导入 Anki 吧。';
  static String get reviewProgressEmptyFiltered => '当前筛选下没有卡片。';
  static String get reviewProgressSeeDetail => '详情';
  static String reviewProgressCardsDue(int total, int due) =>
      '$total 卡 · 到期 $due';
  static String reviewProgressRetentionPct(int pct) => '保留 $pct%';
  static String get playReviewProgressTitle => '复习进度';
  static String get playReviewProgressSubtitle => '记忆曲线与分源统计';

  static String get profileMemoryCurveTitle => '记忆曲线';
  static String get profileRetention => '保留率';
  static String profileRetentionValue(int retention) => '${retention}%';
  static String get profileForecastTitle => '即将复习';
  static String get profileDueToday => '今日到期';
  static String get profileDue7Days => '7 天内';
  static String get profileDue30Days => '30 天内';

  /// Workload buckets only — not a four-stage “mastered” graduation (ADR 0028).
  static String get profileMaturityTitle => '复习阶段';
  static String get profileMaturityNew => '新卡';
  static String get profileMaturityYoung => '巩固中';
  static String get profileMaturityMature => '长期记忆';
  static String get profileMaturityLeech => '顽固';
  static String get profileMasteryTitle => '掌握度（连续）';
  static String profileMasteryValue(int percent) => '$percent%';
  static String get reviewLeechHint => '多次没记住：建议换个语境再学，而不是连刷同一张卡。';

  static String profileReviewsCount(int count) => '$count 次复习';
  static String get profileMemoryCurveEmpty => '复习一些卡片即可查看记忆曲线。';
  static String srsPreviewKnown(int days) => '认识 · 约 ${days}天';
  static String get srsPreviewUnknown => '不认识 · 10 分钟';
  static String profileTotalStudyTimeValue(int totalMinutes) =>
      '${totalMinutes}分';
  static String profileOverallAccuracyValue(int accuracy) => '${accuracy}%';
  static String get profileStatisticsTitle => '统计';
  static String get profileDayStreak => '连续天数';
  static String get profileTotalXp => '总经验值';
  static String get profileGems => '宝石';
  static String get profileShareCardJourneyTitle => '我的语言旅程';
  static String get profileShareCardJourneySubtitle => '每一步成长，都是新的相遇';
  static String get profileShareCardLearnerTag => '学习者 Learner';
  static String get profileShareCardDayStreak => '连续天数';
  static String get profileShareCardTotalXp => '总经验值';
  static String get profileShareCardGems => '宝石';
  static String get profileShareCardLessons => '已完成课程';
  static String get profileShareCardQuote => '每一个词，都是打开新世界的钥匙。';
  static String get profileShareCardQuoteSub => '继续前行，遇见更多美好。';
  static String get profileShareCardFooterTitle => '我在 Turna 学习语言';
  static String get profileShareCardFooterSub => '成长从今天开始，未来无限可能！';
  static String get profileShareText => '看看我在 Turna 上的进度！';

  // ── Characters ──
  static String charactersScriptTitle(String currentLanguage) =>
      '$currentLanguage 字母表';
  static String get charactersVowelsTitle => '元音';
  static String charactersVowelsSubtitle(int count) => '$count 个字符';
  static String get charactersConsonantsTitle => '辅音';
  static String charactersConsonantsSubtitle(int count) => '$count 个字符';
  static String get charactersLearnVowels => '学习元音';
  static String get charactersLearnConsonants => '学习辅音';
  static String get charactersRandomPractice => '随机练习';
  static String get charactersVowelsModeTitle => '元音';
  static String get charactersConsonantsModeTitle => '辅音';
  static String get charactersRandomModeTitle => '随机练习';
  static String get charactersNext => '下一个';

  // ── Content Update ──
  static String get contentUpdateTitle => '课程已更新';
  static String get contentUpdateMessage => '土耳其语课程已更新了新单词和课程。你可以重新开始或继续当前进度。';
  static String get contentUpdateKeepProgress => '保留进度';
  static String get contentUpdateResetProgress => '重置进度';

  // ── Splash ──
  static String get splashReclaiming => '重拾语言学习';
  static String get splashLearnTurkish => 'Learn Turkish • Türkçe öğren';
  static String get splashFreeForever => '免费。永远。';
  static String get splashAppName => 'Turna';
  static String get splashSubtitle => '没有会失去的生命值，没有要补充的体力。\n纯粹的学习。';
  static String get splashGetStarted => '开始使用';
  static String get splashTurkishVoiceMissingTitle => '缺少土耳其语语音数据';
  static String get splashTurkishVoiceMissingBody =>
      '已安装 Google 文字转语音，但尚未下载土耳其语语音包。\n\n打开系统 TTS 设置 → 首选引擎 = Google → 安装土耳其语（Türkçe）语音数据。';
  static String get splashGoogleTtsMissingTitle => 'Google TTS 不可用';
  static String get splashGoogleTtsMissingBody =>
      '此设备未显示 Google 文字转语音（或包可见性阻止了引擎发现）。\n\n安装「Google 语音识别与合成」，设为首选引擎，并下载土耳其语语音。';
  static String get splashGoogleTtsNotReadyTitle => 'Google TTS 不可用';
  static String get splashGoogleTtsNotReadyBody =>
      '首选系统语音未就绪。请安装 Google TTS 和土耳其语语音包。';
  static String get splashKeepCurrentVoice => '保持当前语音';
  static String get splashTtsSettings => 'TTS 设置';
  static String get splashInstallGoogleTts => '安装 Google TTS';
  static String get splashCouldNotOpenStore => '无法打开商店。请手动安装 Google TTS。';

  // ── AI Template ──
  static String get aiTemplateIntro => '新单词';
  static String get aiTemplatePractice => '练习';
  static String get aiTemplateReview => '复习';
  static String get aiTemplateListening => '听力';
  static String get aiTemplateReading => '阅读';
  static String get aiTemplateMastery => '测验';
  static String get aiTemplateMixed => '混合';

  // ── Settings Anki ──
  static String get settingsAnkiNewCardsTitle => 'Anki：每日新卡数';
  static String get settingsAnkiNewCardsSubtitle => '每日最大新 Anki 卡片数量';
  static String get settingsAnkiReviewCardsTitle => 'Anki：每日复习卡数';
  static String get settingsAnkiReviewCardsSubtitle => '每日最大 Anki 复习卡片数量';
  static String get settingsAnkiDailyChallengeTitle => '每日挑战中的 Anki 卡片';
  static String get settingsAnkiDailyChallengeSubtitle => '在每日挑战中包括导入的 Anki 卡片';

  // ── Settings Fun Lab ──
  static String get settingsFunWarning => '趣味实验室\n以下功能仅供娱乐，请勿用于正常学习。';
  static String get settingsFunAutoAnswerTitle => '破解版（自动出答案）';
  static String get settingsFunAutoAnswerSubtitle => '上课时自动选择正确答案并提交';
  static String get settingsFunAutoAnswerOn => '🎮 破解模式已开启 — 上课时将自动答题';
  static String get settingsFunAutoAnswerOff => '破解模式已关闭';
  static String get settingsFunMaxScoreTitle => '一键满级';
  static String get settingsFunMaxScoreSubtitle => '将总分设为 99999';
  static String get settingsFunMaxScoreDialogTitle => '一键满级？';
  static String get settingsFunMaxScoreDialogMessage =>
      '你的真实分数将被覆盖为 99999。此操作无法撤销。';
  static String get settingsFunMaxScoreConfirm => '满级';
  static String get settingsFunMaxScoreDone => '⭐ 总分已设为 99999';
  static String get settingsFunMaxGemsTitle => '无限宝石';
  static String get settingsFunMaxGemsSubtitle => '将宝石设为 99999';
  static String get settingsFunMaxGemsDialogTitle => '无限宝石？';
  static String get settingsFunMaxGemsDialogMessage =>
      '你的真实宝石数将被覆盖为 99999。此操作无法撤销。';
  static String get settingsFunMaxGemsConfirm => '无限宝石';
  static String get settingsFunMaxGemsDone => '💎 宝石已设为 99999';
  static String get settingsFunAllAchievementsTitle => '全成就解锁';
  static String get settingsFunAllAchievementsSubtitle => '解锁所有成就';
  static String get settingsFunAllAchievementsDialogTitle => '全成就解锁？';
  static String get settingsFunAllAchievementsDialogMessage =>
      '所有成就将被标记为已解锁。此操作无法撤销。';
  static String get settingsFunAllAchievementsConfirm => '解锁';
  static String get settingsFunAllAchievementsDone => '🏆 所有成就已解锁';

  // ── Anki sample ──
  static String get ankiTrySample => '试用示例牌组';
  static String get ankiSampleDeckName => '示例 · 土耳其语问候';
  static String get ankiSampleHint => '无需选择文件，立即体验 Anki 导入流程';
  static String get ankiSampleBadge => '示例';

  // ── Profile Anki ──
  static String get profileAnkiDecks => 'Anki 牌组';
  static String get profileAnkiLessons => 'Anki 课程';
  static String get profileAnkiReviews => 'Anki 复习';
  static String get profileQuickActionsTitle => '今日待办';
  static String get profileQuickSrs => '词汇复习';
  static String get profileQuickMistakes => '错题';
  static String get profileQuickAnki => 'Anki 复习';
  static String profileQuickDue(int count) => count > 0 ? '$count' : '—';
  static String get profileKeyMetricsTitle => '概览';
  static String get profileLessonsShort => '完成课程';

  // ── Day Labels ──
  static String get dayMon => '一';
  static String get dayTue => '二';
  static String get dayWed => '三';
  static String get dayThu => '四';
  static String get dayFri => '五';
  static String get daySat => '六';
  static String get daySun => '日';
}
