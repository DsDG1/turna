// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Varnamala';

  @override
  String get commonCancel => '取消';

  @override
  String get commonBack => '返回';

  @override
  String get commonClose => '关闭';

  @override
  String get commonDone => '完成';

  @override
  String get commonRetry => '重试';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonSend => '发送';

  @override
  String get commonApply => '应用';

  @override
  String get commonPractice => '练习';

  @override
  String get commonContinue => '继续';

  @override
  String get commonGotIt => '知道了';

  @override
  String get commonOk => '确定';

  @override
  String get commonSave => '保存';

  @override
  String get commonImport => '导入';

  @override
  String get commonLater => '稍后';

  @override
  String get commonNavLearn => '学习';

  @override
  String get commonNavPlay => '练习';

  @override
  String get commonNavProfile => '我的';

  @override
  String get commonNavSettings => '设置';

  @override
  String get lessonCheck => '核对';

  @override
  String get lessonChecked => '已核对';

  @override
  String get lessonContinueUpper => '继续';

  @override
  String get lessonGotItUpper => '知道了';

  @override
  String get settingsCategoryAccount => '账户';

  @override
  String get settingsCategoryLearning => '学习';

  @override
  String get settingsCategoryAudioHaptics => '声音与触感';

  @override
  String get settingsCategoryAccessibility => '无障碍';

  @override
  String get settingsCategoryAiTools => 'AI 工具';

  @override
  String get settingsCategoryData => '数据';

  @override
  String get settingsCategoryAbout => '关于';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsBack => '返回';

  @override
  String get settingsSoundEffectsTitle => '音效';

  @override
  String get settingsSoundEffectsSubtitle => '为错误和升级播放音效';

  @override
  String get settingsHapticFeedbackTitle => '触感反馈';

  @override
  String get settingsHapticFeedbackSubtitle => '关键操作时振动';

  @override
  String get settingsAiApiConfigTitle => 'AI API 配置';

  @override
  String get settingsAiApiConfigSubtitle => 'Base URL、API 密钥和模型（退出时不保存）';

  @override
  String get settingsDesignCourseAiTitle => '用 AI 设计课程';

  @override
  String get settingsDesignCourseAiSubtitle => '打开 AI 设计对话';

  @override
  String get settingsImportTextbookTitle => '从教材导入';

  @override
  String get settingsImportTextbookSubtitle => '将 Markdown/文本文件转换为课程章节';

  @override
  String get settingsExportDataTitle => '导出数据';

  @override
  String get settingsExportDataSubtitle => '将进度和/或课程内容保存到文件';

  @override
  String get settingsImportDataTitle => '导入数据';

  @override
  String get settingsImportDataSubtitle => '从导出文件恢复进度';

  @override
  String get settingsClearMistakeLogTitle => '清除错题记录';

  @override
  String get settingsClearMistakeLogSubtitle => '删除所有已保存的错题';

  @override
  String get settingsResetProgressTitle => '重置课程进度';

  @override
  String get settingsResetProgressSubtitle => '将所有课程标记为未完成';

  @override
  String get settingsClearMistakeDialogTitle => '清除错题记录？';

  @override
  String get settingsClearMistakeDialogMessage => '这将永久删除所有已保存的错题。';

  @override
  String get settingsClearMistakeConfirm => '清除';

  @override
  String get settingsMistakeLogCleared => '错题记录已清除';

  @override
  String get settingsResetProgressDialogTitle => '重置课程进度？';

  @override
  String get settingsResetProgressDialogMessage =>
      '所有课程完成记录和满分记录都将被清除。此操作无法撤销。';

  @override
  String get settingsResetProgressConfirm => '重置';

  @override
  String get settingsProgressReset => '课程进度已重置';

  @override
  String get settingsImportDataDialogTitle => '导入数据？';

  @override
  String get settingsImportDataDialogMessage => '这将用文件内容覆盖当前进度。此操作无法撤销。建议先导出。';

  @override
  String get settingsImportDataConfirm => '导入';

  @override
  String get settingsCourseSavedRestart => '课程内容已保存；重启后生效';

  @override
  String get settingsProgressRestoredRestart => '进度已恢复——重启应用以生效';

  @override
  String get settingsNothingToImport => '无可导入内容';

  @override
  String settingsImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String settingsExportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String get settingsAiApiConfigSheetTitle => 'AI API 配置';

  @override
  String get settingsAiApiConfigNotSaved => '退出时不保存——仅保留在内存中。';

  @override
  String get settingsBaseUrlLabel => 'Base URL';

  @override
  String get settingsBaseUrlHint => 'https://api.deepseek.com';

  @override
  String get settingsApiKeyLabel => 'API 密钥';

  @override
  String get settingsApiKeyHint => 'sk-...';

  @override
  String get settingsModelLabel => '模型';

  @override
  String get settingsModelHint => 'deepseek-v4-pro';

  @override
  String get settingsSaveConfig => '保存配置';

  @override
  String get settingsExportSheetTitle => '导出数据';

  @override
  String get settingsExportSubtitle => '选择导出文件中包含的内容。';

  @override
  String get settingsExportProgressTitle => '进度数据';

  @override
  String get settingsExportProgressSubtitle => 'SRS、得分、连续学习天数、错题、成就';

  @override
  String get settingsExportCourseTitle => '课程内容';

  @override
  String get settingsExportCourseSubtitle => '内置土耳其语课程 JSON 文件';

  @override
  String get settingsExportButton => '导出';

  @override
  String get settingsExporting => '导出中…';

  @override
  String get settingsAboutVarnamala => '关于 Varnamala';

  @override
  String get settingsOpenSourceLicenses => '开源许可证';

  @override
  String settingsVersionFooter(String version) {
    return '版本 $version';
  }

  @override
  String settingsVersionFooterWithBuild(String version, String build) {
    return '版本 $version ($build)';
  }

  @override
  String get settingsAccountLearnerFallback => '学习者';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsLearningLanguageTitle => '学习语言';

  @override
  String get settingsLearningLanguageSubtitle => '选择你正在学习的语言';

  @override
  String get settingsTtsSpeedTitle => 'TTS 语速';

  @override
  String get settingsTtsSpeedSubtitle => '调整语音播放速度';

  @override
  String settingsTtsSpeedValue(String ttsSpeed) {
    return '${ttsSpeed}x';
  }

  @override
  String get settingsDailyReminderTitle => '每日提醒';

  @override
  String get settingsDailyReminderSubtitle => '温和地提醒复习——无连续天数惩罚';

  @override
  String get settingsReminderTimeTitle => '提醒时间';

  @override
  String settingsReminderTimeSubtitle(String timeLabel) {
    return '当前 $timeLabel';
  }

  @override
  String get settingsTtsChecking => '正在检查设备 TTS 引擎…';

  @override
  String settingsTtsReady(String locale) {
    return 'Google TTS 就绪（$locale）——推荐用于学习';
  }

  @override
  String get settingsTtsGoogleInstalledMissingVoice =>
      'Google 已安装——请在系统 TTS 设置中下载土耳其语语音数据';

  @override
  String get settingsTtsTurkishVoiceMissing => '土耳其语语音未就绪——打开系统 TTS 设置';

  @override
  String settingsTtsGoogleMissing(Object oem) {
    return '未检测到 Google TTS（引擎：$oem）';
  }

  @override
  String get settingsVoiceSourceTitle => '语音来源';

  @override
  String get settingsSystemTts => '系统 TTS';

  @override
  String get settingsVoiceSourceDialogTitle => '语音来源';

  @override
  String get settingsPlaySample => '播放示例（Merhaba）…';

  @override
  String get settingsOpenSystemTts => '打开系统 TTS 设置…';

  @override
  String get settingsInstallGoogleTts => '安装/打开 Google TTS…';

  @override
  String settingsTtsNoVoicePlayed(Object error) {
    return '未播放语音。$error';
  }

  @override
  String get settingsTtsNoVoicePlayedFallback => '未播放语音。请检查 logcat 中的 TTS 错误。';

  @override
  String settingsTtsPlaying(String userLabel) {
    return '正在播放：$userLabel';
  }

  @override
  String get settingsTextSizeTitle => '文字大小';

  @override
  String get settingsTextSizeSubtitle => '全局放大文字';

  @override
  String settingsTextSizeValue(int textScale) {
    return '$textScale%';
  }

  @override
  String get settingsReduceMotionTitle => '减弱动态效果';

  @override
  String get settingsReduceMotionSubtitle => '缩短或禁用动画与过渡';

  @override
  String get settingsHighContrastTitle => '高对比度';

  @override
  String get settingsHighContrastSubtitle => '使用高对比度主题';

  @override
  String get settingsDyslexiaFontTitle => '阅读障碍友好字体';

  @override
  String get settingsDyslexiaFontSubtitle => '切换到 Lexend 字体以便于阅读';

  @override
  String get settingsSensoryReduceTitle => '减少感官刺激';

  @override
  String get settingsSensoryReduceSubtitle => '静音非必要声音和触感';

  @override
  String get settingsFocusModeTitle => '专注模式';

  @override
  String get settingsFocusModeSubtitle => '隐藏主屏幕的轮播欢迎动画';

  @override
  String get aboutTitle => '关于 Varnamala';

  @override
  String get aboutWhatIsTitle => '什么是 Varnamala';

  @override
  String get aboutWhatIsBody =>
      'Varnamala 是一款免费、开源的语言学习应用，专注于帮助你一步步建立真实的词汇和语法能力。它让学习保持离线、无干扰，并由你掌控。';

  @override
  String get aboutHighlightsTitle => '亮点';

  @override
  String get aboutHighlightOfflineTitle => '离线优先';

  @override
  String get aboutHighlightOfflineSubtitle => '随时随地学习';

  @override
  String get aboutHighlightSrsTitle => '间隔复习';

  @override
  String get aboutHighlightSrsSubtitle => '记住更多';

  @override
  String get aboutHighlightInteractionsTitle => '11 种交互';

  @override
  String get aboutHighlightInteractionsSubtitle => '练习所有技能';

  @override
  String get aboutPrivacyTitle => '隐私与本地优先';

  @override
  String get aboutPrivacyBody =>
      '你学习的一切都保留在本设备上。Varnamala 没有云端后端、没有账户、没有追踪——你的进度、错题和设置永不离开手机。卸载应用会删除所有数据。唯一的网络访问是可选的（打开外部链接或你自己配置的 AI 工具）。';

  @override
  String get aboutVersionTitle => '版本与更新日志';

  @override
  String get aboutLinksTitle => '链接';

  @override
  String get aboutUpstreamTitle => '上游项目';

  @override
  String get aboutUpstreamSubtitle => 'github.com/rshrc/Varnamala';

  @override
  String get aboutReportIssueTitle => '报告问题';

  @override
  String get aboutReportIssueSubtitle => 'GitHub Issues';

  @override
  String get aboutViewReleasesTitle => '查看发布';

  @override
  String get aboutViewReleasesSubtitle => '更新日志与下载';

  @override
  String get aboutShareTitle => '分享 Varnamala';

  @override
  String get aboutCreditsTitle => '致谢';

  @override
  String get aboutCreditsOriginal => '原始框架由 Rishi Banerjee 和 Varnamala 开源社区构建。';

  @override
  String get aboutCreditsFork => '本构建是一个本地优先的分叉版本，增加了无障碍设置和课程创作工具。';

  @override
  String get aboutLicense => '基于 GNU 通用公共许可证 v3.0 授权。';

  @override
  String aboutCopyright(String year) {
    return '© $year Varnamala';
  }

  @override
  String get aboutBrandName => 'Varnamala';

  @override
  String get aboutTagline => '学习语言，一步步来。';

  @override
  String aboutVersionLabel(String version) {
    return '版本 $version';
  }

  @override
  String aboutVersionWithBuild(String version, String buildNumber) {
    return '版本 $version（$buildNumber）';
  }

  @override
  String get aboutShareText =>
      '看看 Varnamala——一款免费、开源的语言学习应用！https://github.com/rshrc/Varnamala';

  @override
  String aboutVersionShort(String version) {
    return '版本 $version';
  }

  @override
  String aboutVersionBuild(String buildNumber) {
    return '（$buildNumber）';
  }

  @override
  String get aboutHideChangelog => '隐藏';

  @override
  String get aboutShowChangelog => '显示更新日志';

  @override
  String get aboutReleasesNote => '完整的发布历史，请查看 GitHub 发布页面。';

  @override
  String get aboutMilestone1Title => 'future4 框架';

  @override
  String get aboutMilestone1Body =>
      '完成整洁架构框架：依赖注入整合、音频/内容解耦、SRS 队列基类、GameProvider 外观模式、集成测试、发布流水线。';

  @override
  String get aboutMilestone2Title => '斯瓦希里语 → 土耳其语转向';

  @override
  String get aboutMilestone2Body =>
      '将目标语言迁移到土耳其语，并在第 1 章填充了真实的问候语课程（8 个单词 + 2 个表达）。';

  @override
  String get aboutMilestone3Title => '无障碍设置';

  @override
  String get aboutMilestone3Body =>
      '添加了神经多样性友好选项：文字大小、减弱动态效果、高对比度、阅读障碍友好字体、感官减弱、专注模式。';

  @override
  String get homeAiCourseDesigner => 'AI 课程设计器';

  @override
  String get homeNewCourse => '新建课程';

  @override
  String get homeNewCourseSheetTitle => '新建课程';

  @override
  String get homeDesignWithAi => '用 AI 设计';

  @override
  String get homeDesignWithAiSubtitle => '描述一门课程，让 AI 构建';

  @override
  String get homeImportFromTextbook => '从教材导入';

  @override
  String get homeImportFromTextbookSubtitle => '将 Markdown/文本文件转换为章节';

  @override
  String get homeFromAnki => '从 Anki';

  @override
  String get homeFromAnkiSubtitle => '导入 .apkg/.colpkg 牌组作为课程';

  @override
  String get homeStreakBroken => '你的连续学习中断了。今天重新开始吧。';

  @override
  String ankiImportSuccess(int count) {
    return '成功导入 $count 个单词！';
  }

  @override
  String get ankiImportError => '导入失败，请检查文件格式。';

  @override
  String get homeNewCourseComingSoon => '多语言课程功能即将推出。目前仅支持土耳其语课程。';

  @override
  String get homeNewCourseUseAi => '你也可以使用 AI 课程设计器来创建自定义课程。';

  @override
  String get dialogClose => '关闭';

  @override
  String get playQuickPlayTitle => '快速练习';

  @override
  String get playQuickPlaySubtitle => '尽快匹配单词';

  @override
  String get playMistakeReviewTitle => '错题复习';

  @override
  String playMistakeReviewSubtitleWithCount(int mistakesCount) {
    return '$mistakesCount 个错题——最多练习 10 个';
  }

  @override
  String get playMistakeReviewSubtitleEmpty => '暂无错题记录';

  @override
  String get playReviewTitle => '复习';

  @override
  String playReviewSubtitleWithDue(int srsDue) {
    return '$srsDue 个单词待复习';
  }

  @override
  String get playReviewSubtitleEmpty => '暂无待复习单词';

  @override
  String get playGrammarReviewTitle => '语法复习';

  @override
  String playGrammarReviewSubtitleWithDue(int grammarDue) {
    return '$grammarDue 个语法点待复习';
  }

  @override
  String get playGrammarReviewSubtitleEmpty => '暂无待复习语法';

  @override
  String get playDailyChallengeTitle => '每日挑战';

  @override
  String get playDailyChallengeSubtitle => '随机 15 题——测试你的土耳其语';

  @override
  String get playWeakWordsTitle => '薄弱单词';

  @override
  String playWeakWordsSubtitleWithCount(int weakCount) {
    return '$weakCount 个单词在过去 30 天内错过两次';
  }

  @override
  String get playWeakWordsSubtitleEmpty => '暂无薄弱单词';

  @override
  String get playAnkiReviewTitle => 'Anki 复习';

  @override
  String get playAnkiReviewSubtitle => '复习导入的 Anki 牌组';

  @override
  String get playDictionaryTitle => '词典';

  @override
  String get playDictionarySubtitle => '搜索单词、短语和语法';

  @override
  String get playYourBestTitle => '你的最佳';

  @override
  String get playTotalXp => '总经验值';

  @override
  String get playTitle => '练习';

  @override
  String get playMatchMadness => '匹配狂热';

  @override
  String playXpLabel(int sessionScore) {
    return '$sessionScore XP';
  }

  @override
  String playRoundLabel(int roundsCompleted) {
    return '第 $roundsCompleted 轮';
  }

  @override
  String get playInfiniteRoundsNote => '无限轮次。每次完美完成板后出现新单词。';

  @override
  String get playRoundComplete => '本轮完成！正在加载新单词…';

  @override
  String playTimeUp(int roundsCompleted, int score) {
    return '时间到！你完成了 $roundsCompleted 轮，获得 $score XP。';
  }

  @override
  String get playPlayAgain => '再玩一次';

  @override
  String get playBrilliantRun => '精彩发挥！';

  @override
  String get playChampionEnergy => '冠军之能！';

  @override
  String get playLightningFast => '闪电速度！';

  @override
  String playMatchCount(int matchedCount, int totalCount) {
    return '$matchedCount / $totalCount';
  }

  @override
  String get playDailyClose => '关闭';

  @override
  String get playDailyTitle => '每日挑战';

  @override
  String playDailyQuestion(int current, int total) {
    return '第 $current 题，共 $total 题';
  }

  @override
  String get playDailyChallengeFallback => '每日挑战';

  @override
  String get playDailyContinue => '继续';

  @override
  String get playDailyGotIt => '知道了';

  @override
  String get playDailyNoQuestions => '暂无挑战题目';

  @override
  String get playDailyCompleteFewLessons => '先完成几节课以充实题库。';

  @override
  String get playWeakWordsEmpty => '继续练习——暂无薄弱单词。\n过去 30 天内错过两次的单词会出现在这里。';

  @override
  String get playWeakWordsTitleAppBar => '薄弱单词';

  @override
  String get reviewContinueUpper => '继续';

  @override
  String get reviewGotItUpper => '知道了';

  @override
  String get reviewWeakWordsTitleAppBar => '薄弱单词';

  @override
  String get reviewDoYouKnow => '你认识这个单词吗？';

  @override
  String get reviewDontKnow => '不认识';

  @override
  String get reviewKnowIt => '认识';

  @override
  String get reviewEmptyTitle => '复习';

  @override
  String get reviewEmptyMessage => '你已经全部复习完了。';

  @override
  String get reviewDueMessage => '个单词已到期——下拉刷新';

  @override
  String get reviewNoItemsDue => '暂无待复习项';

  @override
  String reviewDueCountMessage(int dueCount, String dueMessage) {
    return '$dueCount $dueMessage';
  }

  @override
  String get reviewCompletionTitle => '本轮完成！';

  @override
  String get reviewCompletionMessage => '你已复习全部内容。';

  @override
  String get reviewReviewAppBarTitle => '复习';

  @override
  String reviewXpEarned(int xpEarned) {
    return '+$xpEarned XP';
  }

  @override
  String reviewGemsEarned(int gemsEarned) {
    return '+$gemsEarned 宝石';
  }

  @override
  String get reviewReviewMore => '继续复习';

  @override
  String get reviewSrsTitle => '复习';

  @override
  String get reviewSrsSessionComplete => '本轮完成！';

  @override
  String reviewSrsCompletionMessage(int sessionCount) {
    return '你复习了 $sessionCount 项。';
  }

  @override
  String get reviewSrsAppBarTitle => '复习';

  @override
  String reviewSrsTtsSpeed(String ttsSpeed) {
    return '$ttsSpeed x';
  }

  @override
  String get reviewSrsTtsSpeedTooltip => 'TTS 语速';

  @override
  String reviewSrsProgress(int currentIndex, int queueLength) {
    return '$currentIndex / $queueLength';
  }

  @override
  String get reviewSrsShowAnswer => '显示答案';

  @override
  String get reviewSrsPlayPronunciation => '播放发音';

  @override
  String get reviewSrsTapToReveal => '点击显示含义';

  @override
  String reviewSrsLearnedIn(String lessonName) {
    return '所学课程：$lessonName';
  }

  @override
  String reviewSrsFirstSeen(String wordId) {
    return '首次出现：$wordId';
  }

  @override
  String get reviewSrsEntryNotFound => '未找到条目';

  @override
  String reviewSrsPronunciation(String pronunciation) {
    return '/$pronunciation/';
  }

  @override
  String get reviewMistakeReviewTitle => '错题复习';

  @override
  String get reviewViewMistakeList => '查看错题列表';

  @override
  String get reviewNoMistakes => '暂无错题可复习。\n错题会自动记录在此处；每次最多练习 10 个。';

  @override
  String get reviewMyMistakesTitle => '我的错题';

  @override
  String get reviewNoMistakesRecorded => '暂无错题记录';

  @override
  String get reviewKeepItUp => '继续保持！';

  @override
  String get reviewMistakesLabel => '错题';

  @override
  String get reviewWordsLabel => '单词';

  @override
  String get reviewGrammarLabel => '语法';

  @override
  String get reviewUnknownQuestion => '未知问题';

  @override
  String get reviewReviewGrammar => '复习语法';

  @override
  String get reviewGotItNow => '现在我会了';

  @override
  String get reviewYourAnswer => '你的答案';

  @override
  String get reviewCorrectAnswer => '正确答案';

  @override
  String get reviewDash => '—';

  @override
  String reviewGrammarChip(String title) {
    return '语法：$title';
  }

  @override
  String get reviewPracticeTitle => '练习';

  @override
  String get reviewCannotPractice => '此错题无法练习。';

  @override
  String get reviewPracticeMistakeTitle => '错题练习';

  @override
  String get reviewGrammarReviewTitle => '语法复习';

  @override
  String get reviewGrammarEmptyMessage => '你已经全部复习完了。';

  @override
  String get reviewGrammarDueMessage => '个语法点已到期——刷新以加载';

  @override
  String get reviewGrammarSessionComplete => '本轮完成！';

  @override
  String reviewGrammarCompletionMessage(int sessionCount) {
    return '你复习了 $sessionCount 个语法点。';
  }

  @override
  String get reviewGrammarAppBarTitle => '语法复习';

  @override
  String reviewGrammarProgress(int currentIndex, int queueLength) {
    return '$currentIndex / $queueLength';
  }

  @override
  String reviewGrammarPracticeLabel(int practiceIndex, int practiceLength) {
    return '练习 $practiceIndex / $practiceLength';
  }

  @override
  String get reviewGrammarDoYouUnderstand => '你理解这个语法点吗？';

  @override
  String get reviewGrammarNextPractice => '下一个练习';

  @override
  String get reviewGrammarRateGrammar => '为这个语法点评分';

  @override
  String get reviewGrammarShowExplanation => '显示解释';

  @override
  String reviewGrammarLearnedIn(String lessonName) {
    return '所学课程：$lessonName';
  }

  @override
  String reviewGrammarFirstSeen(String wordId) {
    return '首次出现：$wordId';
  }

  @override
  String get reviewGrammarTapToReveal => '点击显示解释';

  @override
  String get reviewGrammarPointNotFound => '未找到语法点';

  @override
  String get lessonFlipCardCaption => '翻牌';

  @override
  String get lessonShowAnswer => '显示答案';

  @override
  String get lessonTapToReveal => '点击下方显示答案';

  @override
  String get lessonHowWellDidYouKnow => '你对这个有多熟悉？';

  @override
  String get lessonAgain => '忘记';

  @override
  String get lessonHard => '困难';

  @override
  String get lessonGood => '良好';

  @override
  String get lessonEasy => '简单';

  @override
  String get lessonPlayAudioLabel => '播放音频';

  @override
  String get lessonFillBlankCaption => '填空';

  @override
  String get lessonFillBlankHint => '___';

  @override
  String get lessonCorrectAnswer => '正确答案';

  @override
  String get lessonListenAndPickCaption => '听音选择';

  @override
  String get lessonSummaryCaption => '概要';

  @override
  String get lessonListenToSummary => '收听概要';

  @override
  String get lessonTapToReplay => '点击喇叭重播';

  @override
  String get lessonTapToListen => '点击喇叭收听';

  @override
  String get lessonMultipleChoiceCaption => '多项选择';

  @override
  String get lessonSelectAllCaption => '选择所有适用项';

  @override
  String lessonSelectAtLeast(int min, int count) {
    return '至少选择 $min 项（已选 $count 项）';
  }

  @override
  String lessonSelectExact(int min, int count) {
    return '选择 $min 项（已选 $count 项）';
  }

  @override
  String lessonSelectRange(int min, int max, int count) {
    return '选择 $min–$max 项（已选 $count 项）';
  }

  @override
  String get lessonReadingComprehensionCaption => '阅读理解';

  @override
  String get lessonShortAnswerCaption => '简答题';

  @override
  String get lessonTypeYourAnswer => '输入你的答案…';

  @override
  String get lessonTrueFalseCaption => '判断题';

  @override
  String get lessonTrue => '正确';

  @override
  String get lessonFalse => '错误';

  @override
  String get lessonArrangeWordsCaption => '排列单词';

  @override
  String get lessonTapRightOrder => '按正确顺序点击单词';

  @override
  String get lessonWordBank => '词库';

  @override
  String get lessonCorrectOrder => '正确顺序';

  @override
  String get lessonTapWordToStart => '点击下方单词开始';

  @override
  String lessonSpeakTerm(String term) {
    return '朗读 $term';
  }

  @override
  String get lessonSpeakContextSentence => '朗读例句';

  @override
  String get lessonTapToContinue => '点击继续';

  @override
  String get lessonItemNotLoaded => '此项无法加载。';

  @override
  String get lessonTranslateCaption => '翻译此句';

  @override
  String get lessonTypeTranslation => '输入译文…';

  @override
  String get lessonCorrectTranslation => '正确译文';

  @override
  String get lessonTypeWhatYouHearCaption => '听写';

  @override
  String get lessonTypeHere => '在此输入…';

  @override
  String get lessonCompleteTitle1 => '课程完成！';

  @override
  String get lessonCompleteSubtitle1 => '出色的专注。你完成了本课。';

  @override
  String get lessonCompleteTitle2 => '真快！';

  @override
  String get lessonCompleteSubtitle2 => '你上升得很快。保持连续学习。';

  @override
  String get lessonCompleteTitle3 => '出色！';

  @override
  String get lessonCompleteSubtitle3 => '每节课都让你更接近精通。';

  @override
  String get lessonPerfectLesson => '完美！全部答对。';

  @override
  String get lessonCorrect => '正确';

  @override
  String get lessonWrong => '错误';

  @override
  String get lessonTime => '用时';

  @override
  String get lessonXp => '经验值';

  @override
  String get lessonAnswerBreakdown => '答题明细';

  @override
  String lessonResultsCount(int correctCount, int totalCount) {
    return '$correctCount / $totalCount';
  }

  @override
  String get lessonBackToCourses => '返回课程';

  @override
  String get lessonAccuracy => '正确率';

  @override
  String lessonPercentValue(int percent) {
    return '$percent%';
  }

  @override
  String lessonQuestionResult(int index, String prompt) {
    return '$index. $prompt';
  }

  @override
  String lessonQuestionAnswer(String correctAnswer) {
    return '答案：$correctAnswer';
  }

  @override
  String get lessonNotYet => '还未通过';

  @override
  String lessonMasteryMessage(int correct, int total, int accuracyPercent) {
    return '你答对 $correct / $total（$accuracyPercent%）。需要 80% 才能通过。再试一次！';
  }

  @override
  String get lessonTryAgain => '再试一次';

  @override
  String lessonDurationSeconds(int seconds) {
    return '$seconds秒';
  }

  @override
  String lessonDurationMinutes(int minutes, int seconds) {
    return '$minutes分$seconds秒';
  }

  @override
  String get lessonAiHelperTooltip => 'AI 课程助手';

  @override
  String get lessonAiHintTooltip => 'AI 提示';

  @override
  String get lessonNoContent => '无内容';

  @override
  String get lessonLessonFallback => '课程';

  @override
  String get lessonCouldNotLoadLesson => '无法加载课程';

  @override
  String get aiNotConfiguredTitle => 'AI 未配置';

  @override
  String get aiNotConfiguredMessageLesson =>
      '在使用 AI 提示前，请在 设置 → 学习 → AI API 配置 中填写 Base URL / API 密钥 / 模型。';

  @override
  String get aiGoToSettings => '前往设置';

  @override
  String get aiCourseDesignerTitle => 'AI 课程设计器';

  @override
  String get aiCourseParametersTooltip => '课程参数';

  @override
  String get aiCourseParametersTitle => '课程参数';

  @override
  String get aiTargetLanguageLabel => '目标语言';

  @override
  String get aiSourceLanguageLabel => '源语言';

  @override
  String get aiTopicLabel => '主题';

  @override
  String get aiLevelLabel => '级别';

  @override
  String get aiUnitsLabel => '单元数';

  @override
  String get aiLessonsPerUnitLabel => '每单元课数';

  @override
  String get aiTemplateLabel => '模板';

  @override
  String get aiGenreBatchTitle => '体裁批量';

  @override
  String get aiGenreBatchSubtitle => '使用 [genre] 标签进行多模板批量生成';

  @override
  String get aiGroundedGenerationTitle => '基于已有内容生成';

  @override
  String get aiGroundedGenerationSubtitle => '复用现有的词汇、表达和语法点';

  @override
  String get aiExtraInstructionsLabel => '额外说明（可选）';

  @override
  String get aiEmptyHintWish => '告诉 AI 你想要什么课程。例如：\n「我想教土耳其语旅行用语——问候和点餐。」';

  @override
  String aiErrorBubble(Object error) {
    return '错误：$error';
  }

  @override
  String get aiCourseGenerated => '课程已生成';

  @override
  String aiAiExplanation(String explanation) {
    return 'AI 说明：$explanation';
  }

  @override
  String get aiSaveToCourseTree => '保存到课程树';

  @override
  String get aiTypeIdea => '输入你的想法…';

  @override
  String get aiSwipeToFinalize => '滑动以确认';

  @override
  String get aiReleaseToFinalize => '释放以确认';

  @override
  String get aiCourseSaved => '课程已保存到数据库。';

  @override
  String aiSaveFailed(Object error) {
    return '保存失败：$error';
  }

  @override
  String get aiTextbookImportTitle => '从教材导入';

  @override
  String get aiTextbookNotConfiguredMessage =>
      '请先在 设置 → AI API 配置 中填写 Base URL / API 密钥 / 模型。';

  @override
  String get aiTextbookTargetLanguageLabel => '目标语言';

  @override
  String get aiTextbookSourceLanguageLabel => '源语言';

  @override
  String get aiTextbookLevelLabel => '级别';

  @override
  String get aiTextbookImportStrategyLabel => '导入策略';

  @override
  String get aiTextbookPickPrompt => '选择一个 Markdown 或文本文件以作为课程章节导入。';

  @override
  String get aiTextbookPickFile => '选择文件';

  @override
  String aiTextbookSelected(String fileName) {
    return '已选择：$fileName';
  }

  @override
  String get aiTextbookParsing => '正在解析文件…';

  @override
  String get aiTextbookExtracting => '正在提取知识…';

  @override
  String get aiTextbookReviewChapters => '审查章节';

  @override
  String aiTextbookChapterChars(int length) {
    return '$length 字符';
  }

  @override
  String get aiTextbookReviewKnowledge => '审查提取的知识';

  @override
  String aiTextbookWords(int count) {
    return '单词：$count';
  }

  @override
  String aiTextbookExpressions(int count) {
    return '表达：$count';
  }

  @override
  String aiTextbookGrammar(int count) {
    return '语法：$count';
  }

  @override
  String get aiTextbookImportComplete => '导入完成！';

  @override
  String aiTextbookErrorFooter(Object error) {
    return '错误：$error';
  }

  @override
  String get aiTextbookExtractKnowledge => '提取知识';

  @override
  String get aiTextbookImportSections => '导入章节';

  @override
  String get aiLessonHelperTitle => 'AI 课程助手';

  @override
  String get aiLessonHelperHint => '例如「让这个更简单」或「添加 3 个练习」';

  @override
  String get aiLessonHelperInstructionLabel => '指令';

  @override
  String get aiLessonHelperChipMakeEasier => '降低难度';

  @override
  String get aiLessonHelperChipMakeHarder => '提高难度';

  @override
  String get aiLessonHelperChipAddExercises => '添加 3 个练习';

  @override
  String get aiLessonHelperChipListening => '改为听力练习';

  @override
  String get aiLessonHelperChipPolish => '优化提示词';

  @override
  String aiLessonHelperError(Object error) {
    return '出错了：$error';
  }

  @override
  String get aiLessonHelperErrorUnknown => '出错了：未知错误';

  @override
  String get aiLessonHelperPreviewTitle => '预览';

  @override
  String get aiLessonHelperTransformationReady => '转换已就绪。点击应用以更新课程。';

  @override
  String get aiLessonHelperTransform => '转换';

  @override
  String aiLessonHelperInvalidJson(Object error) {
    return '无效的课程 JSON：$error';
  }

  @override
  String get aiLessonHelperLessonUpdated => '课程已更新。';

  @override
  String aiLessonHelperUpdateFailed(Object error) {
    return '更新失败：$error';
  }

  @override
  String get aiTutorTitle => 'AI 导师';

  @override
  String aiTutorTitleWithType(String typeLabel) {
    return 'AI 导师 · $typeLabel';
  }

  @override
  String get aiEmptyHintTutor => 'AI 正在为此问题准备解释…';

  @override
  String get aiThinking => 'AI 正在思考…';

  @override
  String get aiAskMore => '继续提问…';

  @override
  String get aiHintTitle => 'AI 提示';

  @override
  String aiHintTitleWithType(String typeLabel) {
    return 'AI 提示 · $typeLabel';
  }

  @override
  String aiHintError(Object error) {
    return '出错了：$error';
  }

  @override
  String get aiHintErrorUnknown => '出错了：未知错误';

  @override
  String get aiHintOpenChat => '打开对话';

  @override
  String get ankiImportTitle => '导入 Anki 牌组';

  @override
  String get ankiImportDialogTitle => '导入 Anki 牌组';

  @override
  String get ankiImportSelectTitle => '导入 Anki 牌组';

  @override
  String get ankiImportSelectSubtitle => '选择从 Anki 导出的 .apkg 或 .colpkg 文件';

  @override
  String get ankiChooseFile => '选择文件';

  @override
  String get ankiParsing => '正在解析 Anki 集合…';

  @override
  String get ankiCollectionSummary => '集合概要';

  @override
  String get ankiDecksLabel => '牌组';

  @override
  String get ankiNotesLabel => '笔记';

  @override
  String get ankiCardsLabel => '卡片';

  @override
  String get ankiMediaFilesLabel => '媒体文件';

  @override
  String get ankiDeckStructure => '牌组结构';

  @override
  String ankiDeckCardCount(int cardCount) {
    return '$cardCount 张卡片';
  }

  @override
  String get ankiNotetypeMapping => '笔记类型映射';

  @override
  String get ankiCollisionReport => '冲突报告';

  @override
  String get ankiNewCards => '新卡片';

  @override
  String get ankiExistingCards => '已存在';

  @override
  String get ankiImportStrategy => '导入策略';

  @override
  String get ankiImportComplete => '导入完成！';

  @override
  String ankiCardsImported(int cardCount) {
    return '已导入 $cardCount 张卡片';
  }

  @override
  String ankiLessonsCreated(int lessonCount) {
    return '已创建 $lessonCount 节课';
  }

  @override
  String ankiVocabAdded(int wordEntryCount) {
    return '已添加 $wordEntryCount 个词汇条目';
  }

  @override
  String get ankiPickFileError => '请选择 .apkg 或 .colpkg 文件。';

  @override
  String ankiPickFileFailed(Object error) {
    return '选择文件失败：$error';
  }

  @override
  String ankiParseFailed(Object error) {
    return '解析失败：$error';
  }

  @override
  String get ankiPreparingImport => '正在准备导入…';

  @override
  String get ankiAssemblingCourse => '正在构建课程树…';

  @override
  String get ankiMigratingSrs => '正在迁移 SRS 状态…';

  @override
  String get ankiSavingMetadata => '正在保存导入元数据…';

  @override
  String ankiImportFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String get ankiStrategyMerge => '合并';

  @override
  String get ankiStrategySkipExisting => '跳过已存在';

  @override
  String get ankiStrategyForceReplace => '强制替换';

  @override
  String get ankiStrategyAppendAsNew => '追加为新';

  @override
  String get ankiStrategyMergeDesc => '更新已存在卡片，添加新卡片';

  @override
  String get ankiStrategySkipExistingDesc => '仅导入不存在的卡片';

  @override
  String get ankiStrategyForceReplaceDesc => '替换所有已存在数据';

  @override
  String get ankiStrategyAppendAsNewDesc => '全部作为新卡片添加（加后缀）';

  @override
  String get ankiReviewTitle => 'Anki 复习';

  @override
  String get ankiNoCardsDue => '暂无待复习的 Anki 卡片。';

  @override
  String get ankiReviewScreenTitle => 'Anki 复习';

  @override
  String get ankiImportNewDeck => '导入新牌组';

  @override
  String ankiCardsDueReview(int totalDue) {
    return '$totalDue 张卡片待复习';
  }

  @override
  String get ankiReviewAll => '全部复习';

  @override
  String get ankiNoDecksTitle => '未导入 Anki 牌组';

  @override
  String get ankiNoDecksSubtitle => '导入 .apkg 文件以开始复习';

  @override
  String get ankiImportDeck => '导入牌组';

  @override
  String ankiQuotaRemaining(int newLeft, int reviewLeft) {
    return '今日剩余：新卡 $newLeft 张，复习 $reviewLeft 张';
  }

  @override
  String get ankiQuotaExhausted => '已达今日上限 — 明天再来';

  @override
  String get ankiUninstallDeck => '移除牌组';

  @override
  String get ankiUninstallConfirmTitle => '移除此牌组？';

  @override
  String get ankiUninstallConfirmBody => '将删除该牌组的卡片、复习进度和媒体文件，此操作无法撤销。';

  @override
  String get ankiDeckRemoved => '牌组已移除';

  @override
  String get coursesCouldNotLoadCourse => '无法加载课程';

  @override
  String get coursesNoSectionsFound => '未找到课程章节。';

  @override
  String get coursesCouldNotLoadSection => '无法加载章节';

  @override
  String get coursesNoUnitsAvailable => '暂无可用单元';

  @override
  String get coursesLoadingCourses => '正在加载课程…';

  @override
  String get coursesLessonTypeNormal => '课程';

  @override
  String get coursesLessonTypeListening => '听力';

  @override
  String get coursesLessonTypeReading => '阅读';

  @override
  String get coursesLessonTypeReview => '复习';

  @override
  String get coursesLessonTypeChallenge => '挑战';

  @override
  String get coursesPerfect => '完美';

  @override
  String coursesUnitProgress(int completedCount, int lessonsCount) {
    return '$completedCount/$lessonsCount';
  }

  @override
  String get coursesChooseSection => '选择章节';

  @override
  String get dictionaryTitle => '词典';

  @override
  String get dictionarySearchHint => '搜索土耳其语或中文…';

  @override
  String get dictionarySearchEmpty => '搜索单词、短语和语法';

  @override
  String get dictionaryNoMatches => '无匹配结果';

  @override
  String get dictionaryKindWord => '单词';

  @override
  String get dictionaryKindPhrase => '短语';

  @override
  String get dictionaryKindGrammar => '语法';

  @override
  String get dictionaryPlayPronunciation => '播放发音';

  @override
  String get onboardingReclaimingTitle => '重拾语言学习';

  @override
  String get onboardingBody =>
      '还记得学习是为了知识，而不是最大化广告收入吗？没有生命值，没有体力，没有付费取胜。纯粹的开源教育。';

  @override
  String get onboardingStartLearning => '开始学习';

  @override
  String get profileTitle => '我的';

  @override
  String get profileShare => '分享';

  @override
  String get profileShareYourProgress => '分享你的进度';

  @override
  String get profileShareButton => '分享';

  @override
  String get profileSharing => '分享中…';

  @override
  String profileShareFailed(Object error) {
    return '无法分享进度：$error';
  }

  @override
  String get profileLearnerFallback => '学习者';

  @override
  String get profileAchievementsTitle => '成就';

  @override
  String profileViewMore(int remainingCount) {
    return '查看另外 $remainingCount 项';
  }

  @override
  String get profileShowLess => '收起';

  @override
  String profileAchievementLevel(int level) {
    return 'Lv.$level';
  }

  @override
  String profileAchievementProgress(int current, int displayTarget) {
    return '$current/$displayTarget';
  }

  @override
  String get profileLearningStatsTitle => '学习统计';

  @override
  String get profileXpToday => '今日经验';

  @override
  String get profileStudyTime => '学习时长';

  @override
  String get profileAccuracy => '正确率';

  @override
  String profileStudyTimeValue(int minutes) {
    return '$minutes分';
  }

  @override
  String profileAccuracyValue(int accuracy) {
    return '$accuracy%';
  }

  @override
  String get profileLast7Days => '最近 7 天';

  @override
  String get profileTotalStudyTime => '总学习时长';

  @override
  String get profileOverallAccuracy => '总正确率';

  @override
  String get profileLessonsDone => '完成课程';

  @override
  String get profileReviewsDone => '复习次数';

  @override
  String profileTotalStudyTimeValue(int totalMinutes) {
    return '$totalMinutes分';
  }

  @override
  String profileOverallAccuracyValue(int accuracy) {
    return '$accuracy%';
  }

  @override
  String get profileStatisticsTitle => '统计';

  @override
  String get profileDayStreak => '连续天数';

  @override
  String get profileTotalXp => '总经验值';

  @override
  String get profileGems => '宝石';

  @override
  String profileShareCardLearning(String displayName) {
    return '$displayName 正在学习';
  }

  @override
  String get profileShareCardDayStreak => '连续天数';

  @override
  String get profileShareCardTotalXp => '总经验值';

  @override
  String get profileShareCardGems => '宝石';

  @override
  String get profileShareCardLessons => '课程';

  @override
  String get profileShareCardJoinMe => '来 Varnamala 一起学！';

  @override
  String get profileShareText => '看看我在 Varnamala 上的进度！';

  @override
  String charactersScriptTitle(String currentLanguage) {
    return '$currentLanguage 字母表';
  }

  @override
  String get charactersVowelsTitle => '元音';

  @override
  String charactersVowelsSubtitle(int count) {
    return '$count 个字符';
  }

  @override
  String get charactersConsonantsTitle => '辅音';

  @override
  String charactersConsonantsSubtitle(int count) {
    return '$count 个字符';
  }

  @override
  String get charactersLearnVowels => '学习元音';

  @override
  String get charactersLearnConsonants => '学习辅音';

  @override
  String get charactersRandomPractice => '随机练习';

  @override
  String get charactersVowelsModeTitle => '元音';

  @override
  String get charactersConsonantsModeTitle => '辅音';

  @override
  String get charactersRandomModeTitle => '随机练习';

  @override
  String get charactersNext => '下一个';

  @override
  String get contentUpdateTitle => '课程已更新';

  @override
  String get contentUpdateMessage => '土耳其语课程已更新了新单词和课程。你可以重新开始或继续当前进度。';

  @override
  String get contentUpdateKeepProgress => '保留进度';

  @override
  String get contentUpdateResetProgress => '重置进度';

  @override
  String get splashReclaiming => '重拾语言学习';

  @override
  String get splashLearnTurkish => 'Learn Turkish • Türkçe öğren';

  @override
  String get splashFreeForever => '免费。永远。';

  @override
  String get splashAppName => 'Varnamala';

  @override
  String get splashSubtitle => '没有会失去的生命值，没有要补充的体力。\n纯粹的学习。';

  @override
  String get splashGetStarted => '开始使用';

  @override
  String get splashTurkishVoiceMissingTitle => '缺少土耳其语语音数据';

  @override
  String get splashTurkishVoiceMissingBody =>
      '已安装 Google 文字转语音，但尚未下载土耳其语语音包。\n\n打开系统 TTS 设置 → 首选引擎 = Google → 安装土耳其语（Türkçe）语音数据。';

  @override
  String get splashGoogleTtsMissingTitle => 'Google TTS 不可用';

  @override
  String get splashGoogleTtsMissingBody =>
      '此设备未显示 Google 文字转语音（或包可见性阻止了引擎发现）。\n\n安装「Google 语音识别与合成」，设为首选引擎，并下载土耳其语语音。';

  @override
  String get splashGoogleTtsNotReadyTitle => 'Google TTS 不可用';

  @override
  String get splashGoogleTtsNotReadyBody =>
      '首选系统语音未就绪。请安装 Google TTS 和土耳其语语音包。';

  @override
  String get splashKeepCurrentVoice => '保持当前语音';

  @override
  String get splashTtsSettings => 'TTS 设置';

  @override
  String get splashInstallGoogleTts => '安装 Google TTS';

  @override
  String get splashCouldNotOpenStore => '无法打开商店。请手动安装 Google TTS。';

  @override
  String get aiTemplateIntro => '新单词';

  @override
  String get aiTemplatePractice => '练习';

  @override
  String get aiTemplateReview => '复习';

  @override
  String get aiTemplateListening => '听力';

  @override
  String get aiTemplateReading => '阅读';

  @override
  String get aiTemplateMastery => '测验';

  @override
  String get aiTemplateMixed => '混合';

  @override
  String get settingsUiLanguageTitle => '应用语言';

  @override
  String get settingsUiLanguageSubtitle => '选择界面语言';

  @override
  String get settingsUiLanguageSystem => '跟随系统';
}
