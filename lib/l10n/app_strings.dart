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
  static String get commonMoreActions => '更多操作';
  static String get commonImport => '导入';
  static String get commonLater => '稍后';
  static String get commonUndo => '撤销';
  static String get commonRedo => '重做';
  static String get commonCollapse => '收起';
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
  static String get settingsCategoryAccount => '个性化与目标';
  static String get settingsCategoryAccountSubtitle => '头像装扮、宝石与每日目标';
  static String get settingsCategoryLearning => '学习';
  static String get settingsCategoryLearningSubtitle => '语言、语速、提醒与 Anki';

  static String get settingsCategoryAppearanceSound => '外观与声音';
  static String get settingsCategoryAppearanceSoundSubtitle => '主题、音效与触感反馈';
  static String get settingsCategoryAccessibility => '无障碍';
  static String get settingsCategoryAccessibilitySubtitle => '字号、对比度、动态与专注';
  static String get settingsCategoryDataBackup => '数据与备份';
  static String get settingsCategoryDataBackupSubtitle => '导入、导出、远程备份与重置';
  static String get settingsCategoryAdvanced => '高级';
  static String get settingsCategoryAdvancedSubtitle => 'AI 连接、存储、诊断与兼容性';
  static String get settingsCategoryAbout => '关于 Turna';
  static String get settingsCategoryAboutSubtitle => '版本、更新日志与链接';
  static String get settingsCategoryFunLab => '开发者实验室';
  static String get settingsCategoryFunLabSubtitle => '仅开发环境可用，正式版不展示';
  static String get settingsGroupPersonal => '个人';
  static String get settingsGroupLearning => '学习体验';
  static String get settingsGroupDataSystem => '数据与系统';
  static String get settingsGroupProduct => '产品';
  static String get settingsTitle => '设置';
  static String get settingsLandingQuickTitle => '常用设置';
  static String get settingsLandingThemeTitle => '主题';
  static String get settingsLandingReminderOff => '未开启';
  static String settingsLandingPersonalSummary({
    required String displayName,
    required int dailyXp,
    required int studyMinutes,
  }) =>
      '$displayName · 每日 $dailyXp XP / $studyMinutes 分钟';
  static String get settingsLearningPrefsTitle => '学习偏好';
  static String get settingsAnkiSectionTitle => 'Anki 复习';
  static String get settingsAudioSectionTitle => '声音与触感';
  static String get settingsA11ySectionTitle => '阅读与感官';
  static String get settingsAppearanceSectionTitle => '外观';
  static String get settingsAiSectionTitle => 'AI 工具';
  static String get settingsDataSectionTitle => '数据管理';
  static String get settingsLearningRecordsTitle => '学习记录';
  static String get settingsDangerZoneTitle => '危险操作';
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

  // ── Advanced settings (高级首页四入口 + 旧版与兼容性) ──
  static String get settingsAdvancedIntroBanner =>
      '高级设置可能影响兼容性与性能，但每一项都说明影响范围。日常使用无需进入此页。';
  static String get settingsAdvancedAiConnectionTitle => 'AI 连接';
  static String get settingsAdvancedAiConnectionSubtitle =>
      '服务商、凭据、模型与连接测试（涉及密钥和网络）';
  static String get settingsAdvancedStorageTitle => '存储与性能';
  static String get settingsAdvancedStorageSubtitle =>
      '空间分类、缓存、垃圾与运行诊断（包含清理操作）';
  static String get settingsAdvancedSystemHealthTitle => '系统健康与诊断';
  static String get settingsAdvancedSystemHealthSubtitle => '数据库状态、功能状态与脱敏诊断摘要';
  static String get settingsAdvancedLegacyTitle => '旧版与兼容性';
  static String get settingsAdvancedLegacySubtitle =>
      'Anki 渲染与 WebView JavaScript（可能影响内容显示）';
  static String get settingsLegacySectionDisplayTitle => 'Anki 显示兼容';
  static String get settingsLegacySectionRecoveryTitle => '内容恢复';
  static String get settingsLegacyForceDisableJsTitle =>
      '强制禁用 WebView JavaScript';
  static String get settingsLegacyForceDisableJsSubtitle =>
      '适用：不信任任何卡片脚本。副作用：加密牌组显示密文。默认：关闭。修改后需重新打开卡片。';
  static String get settingsLegacyResetDefaultsTitle => '恢复兼容性默认值';
  static String get settingsLegacyResetDefaultsSubtitle =>
      '将以上开关恢复为默认值，不删除任何用户数据';
  static String get settingsLegacyResetDefaultsConfirm => '恢复默认';
  static String get settingsLegacyResetDefaultsDone => '已恢复兼容性默认值';

  // ── External links (Plan 2 §4.7/§7.3) ──
  static String get externalLinkNotConfigured => '此链接尚未在此构建中配置，暂不可用';
  static String get externalLinkInvalidScheme => '链接地址不合法（仅允许 https），已禁用';
  static String get externalLinkOpenFailed => '打开链接失败';
  static String get externalLinkCopyAddress => '复制地址';
  static String get externalLinkDisabledSuffix => '（未配置）';
  static String get aboutLinksNotConfiguredNote =>
      '项目主页、问题反馈、发布页与 GUI 平台的正式地址尚未确认；'
      '确认后会在此提供。当前不会打开任何未经验证的链接。';

  // ── Remote backup (WebDAV) ──
  static String get settingsRemoteBackupTitle => '远程备份';
  static String get settingsRemoteBackupSubtitle => '通过 WebDAV 备份与恢复全部学习数据';
  static String get settingsRemoteBackupUnsupported => '当前平台暂不支持远程备份';
  static String get remoteBackupServerSection => '服务器';
  static String get remoteBackupServerUrlLabel => '服务器地址';
  static String get remoteBackupServerUrlHint => 'https://dav.example.com/dav';
  static String get remoteBackupUsernameLabel => '用户名';
  static String get remoteBackupUsernameHint => 'WebDAV 账号';
  static String get remoteBackupPasswordLabel => '密码';
  static String get remoteBackupPasswordHint => 'WebDAV 密码（坚果云请用应用密码）';
  static String get remoteBackupTestConnection => '测试连接';
  static String get remoteBackupTesting => '正在测试…';
  static String get remoteBackupSaveAndTest => '保存并测试';
  static String get remoteBackupSaving => '正在保存…';
  static String get remoteBackupTestOk => '连接成功，目录已就绪';
  static String remoteBackupTestFailed(Object error) => '连接失败：$error';
  static String get remoteBackupHint =>
      '备份会上传到你自己的 WebDAV 服务器（Nextcloud、Alist 等，后续支持坚果云）。包含进度、课程、Anki 牌组与媒体；不含服务器密码与 AI API key。';
  static String get remoteBackupBackupSection => '备份';
  static String get remoteBackupIncludeMediaTitle => '包含媒体文件';
  static String get remoteBackupIncludeMediaSubtitle => 'Anki 卡组的图片/音频，按内容增量上传';
  static String get remoteBackupBackupNow => '立即备份';
  static String get remoteBackupNoBackupYet => '尚未备份过';
  static String remoteBackupLastBackup(Object time, Object size) =>
      '上次备份：$time（核心包 $size）';
  static String get remoteBackupRemoteStatusLoading => '正在读取服务器状态…';
  static String remoteBackupRemoteStatusError(Object error) =>
      '读取服务器状态失败：$error';
  static String remoteBackupRemoteStatus(Object time, Object device) =>
      '服务器最新备份：$time（来自 $device）';
  static String get remoteBackupPhaseCollectingPrefs => '正在收集进度数据…';
  static String get remoteBackupPhaseSnapshottingCourseDb => '正在快照课程数据库…';
  static String get remoteBackupPhaseSnapshottingOfficialDbs => '正在快照 Anki 数据…';
  static String remoteBackupPhaseHashingMedia(Object done, Object total) =>
      '正在扫描媒体（$done/$total）…';
  static String get remoteBackupPhasePackingArchive => '正在打包备份…';
  static String remoteBackupPhaseUploadingMedia(
          Object uploaded, Object skipped) =>
      '正在上传媒体（新增 $uploaded，已跳过 $skipped）…';
  static String get remoteBackupPhaseUploadingCore => '正在上传核心包…';
  static String remoteBackupSuccess(Object size) => '备份完成（核心包 $size）';
  static String remoteBackupFailed(Object error) => '备份失败：$error';
  static String get remoteBackupRestoreSection => '恢复';
  static String get remoteBackupRestoreFromRemote => '从远程恢复';
  static String get remoteBackupRestoreSubtitle => '下载最近备份，重启应用后覆盖本机数据';
  static String get remoteBackupRestoreDialogTitle => '从远程恢复？';
  static String get remoteBackupRestoreDialogMessage =>
      '将下载最近一次远程备份，并在重启应用后覆盖本机的进度、课程与 Anki 数据。此操作不可撤销。';
  static String get remoteBackupRestoreConfirm => '下载并覆盖';
  static String get remoteBackupRestoringCore => '正在下载核心包…';
  static String remoteBackupRestoringMedia(Object done, Object total) =>
      '正在下载媒体（$done/$total）…';
  static String get remoteBackupRestoreStagedTitle => '恢复包已就绪';
  static String get remoteBackupRestoreStagedMessage =>
      '备份已下载并校验完成。重启应用后将自动完成恢复。';
  static String remoteBackupRestoreFailed(Object error) => '恢复准备失败：$error';
  static String remoteBackupBlockedNotice(Object reason) => '上次恢复未执行：$reason';

  // ── Beginner guide ──
  static String get beginnerGuideTitle => '新手指南';
  static String get beginnerGuideEntry => '新手指南';
  static String get beginnerGuideEntrySubtitle => '了解核心功能与使用方法';
  static String get beginnerGuideIntro => '点功能即可跳转体验';
  static String get beginnerGuideSectionLearn => '学习';
  static String get beginnerGuideSectionPractice => '练习与复习';
  static String get beginnerGuideSectionTools => '工具';
  static String get beginnerGuideSectionProfile => '我的';
  static String get beginnerGuideTryNow => '去体验';
  static String get beginnerGuideReturnBubble => '返回新手指南';
  static String get beginnerGuideReturnDismissTooltip => '关闭提示';
  static String get beginnerGuideLearnTitle => '学习课程';
  static String get beginnerGuideCourseMgmtTitle => '课程管理';
  static String get beginnerGuidePlayTitle => '练习中心';
  static String get beginnerGuideSrsTitle => '间隔复习';
  static String get beginnerGuideMistakesTitle => '错题本';
  static String get beginnerGuideWeakWordsTitle => '弱词专项';
  static String get beginnerGuideDictionaryTitle => '词典';
  static String get beginnerGuideAiTitle => 'AI 助手';
  static String get beginnerGuideStatsTitle => '学习统计';
  static String get settingsResetLearningDefaultsTitle => '重置为默认';
  static String get settingsResetLearningDefaultsSubtitle =>
      '恢复语速、提醒与 Anki 限额等学习偏好';
  static String get settingsResetLearningDefaultsDialogTitle => '重置学习设置为默认？';
  static String get settingsResetLearningDefaultsDialogMessage =>
      '将恢复语速、每日提醒和 Anki 每日限额等默认值。不会更改学习语言或课程进度。';
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
  static String get settingsProgressRestored => '导入完成，学习进度与设置已恢复';
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

  // ── Cosmetics (avatar rings) ──
  static String get cosmeticsTitle => '装扮';
  static String get cosmeticsSubtitle => '用宝石兑换头像环';
  static String get cosmeticsRingMist => '晨雾';
  static String get cosmeticsRingReed => '芦苇';
  static String get cosmeticsRingLake => '湖光';
  static String get cosmeticsFree => '免费';
  static String get cosmeticsInUse => '使用中';
  static String get cosmeticsUse => '使用';
  static String get cosmeticsRedeem => '兑换';
  static String get cosmeticsInsufficientGems => '宝石不足';
  static String get cosmeticsRedeemed => '已兑换并使用';
  static String get cosmeticsEquipped => '已使用';
  static String get cosmeticsOwned => '已拥有';
  static String cosmeticsGemsBalance(int gems) => '宝石 $gems';
  static String cosmeticsRingPrice(int price) => '$price';

  static String cosmeticsRingTitle(String id) {
    switch (id) {
      case 'ring_reed':
        return cosmeticsRingReed;
      case 'ring_lake':
        return cosmeticsRingLake;
      case 'ring_sunset':
        return '落日';
      case 'ring_aurora':
        return '极光';
      case 'ring_obsidian':
        return '曜石';
      case 'ring_mist':
      default:
        return cosmeticsRingMist;
    }
  }

  static String cosmeticsSlotTitle(String slot) => switch (slot) {
        'avatarRing' => '头像环',
        'profileTheme' => '个人页主题',
        'completionEffect' => '完成效果',
        _ => '装扮',
      };

  static String cosmeticsItemTitle(String id) => switch (id) {
        'theme_profile_mist' => '湿地晨雾',
        'theme_profile_sunrise' => '安纳托利亚晨光',
        'effect_reed_bloom' => '芦苇绽放',
        'effect_lake_glow' => '湖光闪耀',
        _ => cosmeticsRingTitle(id),
      };

  static String get settingsThemeLight => '浅色';
  static String get settingsThemeDark => '深色';
  static String get settingsThemeSystem => '跟随系统';
  static String get settingsLearningLanguageTitle => '学习语言';
  static String get settingsLearningLanguageSubtitle => '选择你正在学习的语言';
  static String get settingsTtsFeatureTitle => '朗读功能';
  static String get settingsTtsFeatureSubtitle =>
      '开启后自动朗读生效，并可在「课程管理」中为每门课程配置';
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
  static String settingsTextSizeValue(int textScale) => '$textScale%';
  static String get settingsCardTextSizeTitle => '卡面文字大小';
  static String get settingsCardTextSizeSubtitle => '放大复习卡片内的文字';
  static String get settingsReduceMotionTitle => '减弱动态效果';
  static String get settingsReduceMotionSubtitle => '缩短或禁用动画与过渡';
  static String get settingsHighContrastTitle => '高对比度';
  static String get settingsHighContrastSubtitle => '使用高对比度主题';
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
  static String get accountAvatarChangeTitle => '选择角色';
  static String get accountAvatarChangeHint => '点一下卡片即可切换';
  static String get accountAvatarChangeTooltip => '换头像';
  static String accountAvatarName(String name) => name;
  static String get accountAvatarReset => '重置默认';
  static String get accountAvatarResetTooltip => '回到默认头像';
  static String get accountAvatarResetDone => '已重置为默认头像';
  static String accountAvatarChangedDone(String name) => '已切换为 $name';
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
  static String get aboutCreditsFork =>
      '本构建是一个本地优先的分叉版本，增加了无障碍设置，并在 tool/gui/ 中提供了面向创作者的桌面端课程编辑器。';
  static String get aboutToolGuiLinkTitle => '课程编辑器（桌面端）';
  static String get aboutToolGuiLinkSubtitle => '可视化课程编辑 · AI 课程工坊 · 一键发布';
  static String get aboutToolsTitle => '配套工具';
  static String get aboutToolGuiName => 'GUI 课程编辑器';
  static String get aboutToolGuiDesc => 'PySide6 桌面应用，课程树 / AI 工坊 / 校验与发布';
  static String get aboutToolCliName => '课程内容 CLI';
  static String get aboutToolCliDesc =>
      'course_cli.py：校验 / lint / CSV / 音频清单 / diff';
  static String get aboutToolDocsName => '项目文档';
  static String get aboutToolDocsDesc => 'project-guide 与 authoring/ 下的创作者指南';
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
  static String get changelogCopyButton => '一键复制';
  static String get changelogCopied => '已复制到剪贴板';
  static String get changeloadFallback => '无法读取 assets/changelog.md，已切换到内置版本';

  // ── About tabs ──
  static String get aboutTabAbout => '关于';
  static String get aboutTabChangelog => '更新日志';

  // ── Quick Start ──
  static String get quickStartLoadFallback => '无法读取 assets/quick_start.md';

  // ── Privacy details ──
  // Settings → 关于 → 隐私详情 页面文案。互联网隐私政策模板:
  // 数据收集 / 存储 / 网络 / 第三方 / 用户权利 / 联系方式 / 政策更新。
  static String get privacyDetailsTitle => '隐私详情';
  static String get privacyDetailsEntry => '隐私详情';
  static String get privacyDetailsEntrySubtitle => '数据收集、网络行为与你的权利';
  static String get privacyDetailsLastUpdated => '最后更新：2026 年 8 月';
  // 概述
  static String get privacyDetailsOverviewTitle => '概述';
  static String get privacyDetailsOverviewIntro => 'Turna 在隐私与数据上的整体立场';
  static String get privacyDetailsOverviewBody =>
      'Turna 是一款本地优先的语言学习应用。我们没有云端后端、没有账户体系、不接入任何分析或广告 SDK。默认情况下，你的一切学习数据都只保存在你自己的设备上，未经你主动允许，绝不离开本机。';
  // 我们不收集什么
  static String get privacyDetailsNotCollectTitle => '我们不收集什么';
  static String get privacyDetailsNotCollectIntro => '明确列出 Turna 不会主动做的事';
  static String get privacyDetailsNotCollectBody =>
      'Turna 不会主动收集或上传：账号信息（无注册）、邮箱或手机号、姓名或头像、通讯录与位置、设备唯一标识符（IDFA / OAID / IMEI 等）、广告标识符、崩溃分析或性能埋点、任何形式的用户行为画像。';
  // 数据存储
  static String get privacyDetailsStorageTitle => '数据存储';
  static String get privacyDetailsStorageIntro => '你的学习数据存放在哪里';
  static String get privacyDetailsStorageBody =>
      '课程进度、SRS 复习数据、错题本、收藏、成就、设置项、皮肤与主题等数据，全部保存在本机 SQLite 数据库与 SharedPreferences 中，受系统沙箱保护。卸载应用将一并删除这些数据——我们没有副本可恢复。建议定期使用「设置 → 数据 → 导出数据」进行本地备份，或配置「设置 → 数据 → 远程备份」将完整备份（含 Anki 牌组与媒体）上传到你自己的 WebDAV 服务器；远程备份的账号密码仅保存在本机，备份包不含该密码与 AI API key。';
  // 网络访问
  static String get privacyDetailsNetworkTitle => '网络访问';
  static String get privacyDetailsNetworkIntro =>
      'Turna 的网络行为分两类:非 AI 默认完全离线,AI 由你决定';
  static String get privacyDetailsNonAiTitle => '非 AI 功能';
  static String get privacyDetailsNonAiIntro => '默认完全离线,无需任何网络请求';
  static String get privacyDetailsNonAiBody =>
      '课程学习、间隔复习、错题练习、每日挑战、词典查询、统计与提醒等所有内置功能均完全离线运行，不发起任何网络请求。你可以关闭设备的移动数据和 Wi-Fi 正常使用所有非 AI 功能，不会出现任何网络依赖。';
  static String get privacyDetailsAiTitle => 'AI 功能';
  static String get privacyDetailsAiIntro => '联网行为由你在 AI API 配置中选择的平台决定';
  static String get privacyDetailsAiBody =>
      'AI 助手（自由问答、伴学、诊断、词典扩展、AI 课程设计、教材导入、Anki 卡片讲解等）仅在你主动配置并调用时才会联网。具体访问哪个服务器、传输哪些内容、是否留存日志，完全取决于你在「设置 → AI 工具 → AI API 配置」中选择的 AI 服务提供平台（例如 DeepSeek、OpenAI、自建网关、任何兼容 OpenAI 协议的端点等）。Turna 不代理、不中转、不存储你的对话到云端——所有请求直接由本机发往你配置的 Base URL，API 密钥仅保存在本机偏好中（退出输入框即丢弃输入），不会上传到任何第三方。';
  // 可选网络行为：外部链接
  static String get privacyDetailsExternalLinksTitle => '可选网络行为：外部链接';
  static String get privacyDetailsExternalLinksIntro => '打开外部链接时 Turna 的行为';
  static String get privacyDetailsExternalLinksBody =>
      '当你在应用内点击 GitHub 仓库、问题反馈、发布页、课程编辑器等链接时，系统会调用操作系统的浏览器打开对应外部网页。该行为由你主动触发，Turna 不在打开前向这些网站发送任何数据。';
  // 你的权利与控制
  static String get privacyDetailsYourRightsTitle => '你的权利与控制';
  static String get privacyDetailsYourRightsIntro => '你对自己的数据拥有完全控制';
  static String get privacyDetailsYourRightsBody =>
      '你始终拥有自己的数据。可随时在「设置 → 数据」中：导出完整进度为本地 JSON 文件；从导出文件恢复；清除错题记录；重置课程进度；或直接卸载应用彻底抹除全部数据。AI 相关数据可随时在「设置 → AI 工具 → AI API 配置」中清空 API 密钥、切换或停用。';
  // 政策更新
  static String get privacyDetailsUpdatesTitle => '政策更新';
  static String get privacyDetailsUpdatesIntro => '政策的变更与通知方式';
  static String get privacyDetailsUpdatesBody =>
      '我们可能在产品迭代中调整本政策。任何实质变更都会随版本更新发布，并在「设置 → 关于 → 更新日志」中说明。我们不会以削弱离线优先承诺或扩大默认数据收集范围的方式修改本页内容。';
  // 联系方式
  static String get privacyDetailsContactTitle => '联系方式';
  static String get privacyDetailsContactIntro => '如有问题,通过这里反馈';
  static String get privacyDetailsContactBody =>
      '如对本政策或数据实践有任何疑问，欢迎通过 GitHub Issues 反馈：github.com/rshrc/Varnamala/issues。';
  static String get aboutPrivacyOpenDetails => '查看完整隐私详情 →';

  // ── Transparency log (隐私详情页底部 pill 跳的页面)──
  static String get transparencyPillHint => '一般的 app 会读什么？';
  static String get transparencyPillHintSubtitle => '点我看 Turna 自己的透明日志';
  static String get transparencyTitle => '透明度报告';
  static String get transparencyIntro =>
      '「我说不收集,那 Turna 自己到底产了什么日志?」——下面是你能看到的全部。';
  static String get transparencyOpsTitle => '最近操作日志';
  static String get transparencyOpsEmpty => '本会话暂无 info 级日志。';
  static String get transparencyErrorTitle => '错误日志';
  static String get transparencyErrorEmpty => '本会话一切正常,没有 warn / error。';
  static String get transparencyDeviceTitle => '一般数据';
  static String get transparencyDeviceIntro => '一次性读取,仅在内存展示:';
  static String get transparencyDeviceAppVersion => '应用版本';
  static String get transparencyDevicePlatform => '运行平台';
  static String get transparencyDeviceOs => '操作系统';
  static String get transparencyDeviceScreen => '屏幕尺寸';
  static String get transparencyDeviceLocale => '系统语言';
  static String get transparencyDeviceTimezone => '时区';
  static String get transparencyFooter =>
      '上述内容仅保存在本机:`transparency_log.jsonl`(应用沙箱内)与本次会话内存。绝不联网、绝不主动上传。';
  static String get transparencyClearAll => '清空本机日志';
  static String get transparencyClearAllDone => '本机日志已清空';
  static String get transparencyLevelInfo => '信息';
  static String get transparencyLevelWarn => '警告';
  static String get transparencyLevelError => '错误';
  static String transparencyLogCount(int n) => '共 $n 条';
  static String get transparencyLogFileLabel => '本机文件';

  // ── Home ──
  static String get homeAiCourseDesigner => 'AI 课程设计器';
  static String get homeNewCourseSheetTitle => '新建课程';
  static String get homeDesignWithAi => '用 AI 设计';
  static String get homeDesignWithAiSubtitle => '描述一门课程，让 AI 构建';
  static String get homeImportFromTextbook => '从教材导入';
  static String get homeImportFromTextbookSubtitle => '将 Markdown/文本文件转换为章节';
  static String get homeFromAnki => '从 Anki';
  static String get homeFromAnkiSubtitle => '导入 .apkg 牌组作为课程';
  static String get homeStreakBrokenTitle => '连续学习中断了';
  static String get homeStreakBroken => '你的连续天数已归零。今天学一点，重新开始吧。';
  static String get dialogClose => '关闭';

  // ── Course management ──
  static String get courseManagementTitle => '课程管理';
  static String get courseManagementCurrentBadge => '当前';
  static String get courseManagementDefaultBadge => '默认';
  static String get courseManagementBuiltinSubtitle => '默认课程，不可删除';
  static String get courseManagementMyCourses => '我的课程';
  static String courseManagementCardCount(int count) => '$count 张卡片';
  static String get courseManagementRemoveCourse => '移除课程';
  static String get courseManagementImportTitle => '从 Anki 导入课程';
  static String get courseManagementAddTitle => '添加课程';

  // Per-course smart-TTS settings (course management page).
  static String get courseTtsSettingsTitle => '朗读设置';
  static String get courseTtsAutoReadTitle => '点击自动朗读';
  static String get courseTtsAutoReadSubtitle => '点击选项或翻开卡片时自动朗读';
  static String get courseTtsNativeLangTitle => '翻译/母语语言';
  static String get courseTtsNativeLangSubtitle => '纯拉丁字母文本的朗读语音（如英语译文）';

  // ── Play ──

  // ── Playground（语言课程自由练习场）──
  static String get playgroundTitle => 'Playground';

  // ── Playground AI 工具入口（Plan 3 §19.2）──
  static String get playgroundAiToolsTitle => 'AI 语言工具';
  static String get playgroundAiToolQa => '问一问';
  static String get playgroundAiToolSentence => '句子纠错';
  static String get playgroundAiToolRoleplay => '情景对话';

  static String get playgroundComingSoon => '即将推出';
  static String get playgroundChineseName => '自由练习场';

  // ── 内容创作退场 tombstone（Plan 3 §19.4）──
  static String get authoringMovedTitle => '内容创作已迁移';
  static String get authoringMovedBody =>
      '移动端不再提供课程生成、教材导入和结构编辑。请前往 GUI 平台完成内容创作，'
      '移动端继续负责学习与复习。';
  static String get authoringMovedOpenGui => '打开 GUI 平台';
  static String get authoringMovedGuiUnconfigured =>
      'GUI 平台地址尚未在此构建中配置，确认后将提供入口。不会打开未经确认的链接。';
  static String get authoringMovedDraftsKept => '你已有的创作草稿不会因此被删除。';
  static String get playgroundHeroSubtitle => '自由组合题型，随时练几分钟';

  static String get aiCardExplainUnsupported => '此卡片暂不支持 AI 解释';
  static String get playgroundStartAction => '开始探索';
  static String get playgroundSmartStartTitle => '智能开练';
  static String get playgroundSmartStartCaption => '3 分钟 · 标准 · 智能混合';
  static String get playgroundSmartStartAction => '立即开始';
  static String get playgroundSmartStartSoon => '智能开练即将上线，敬请期待';
  static String get playgroundBlockedToast => 'Playground 仅在语言课程中可用';
  static String get playgroundBlockedTitle => '当前课程不支持 Playground';
  static String get playgroundBlockedMessage => '切换回语言课程后即可自由练习';
  static String get playgroundContentScopeTitle => '练什么';
  static String get playgroundModeTitle => '练习模式';
  static String get playgroundScopeRecent => '最近学习';
  static String get playgroundScopeCurrentUnit => '当前单元';
  static String get playgroundScopeWholeCourse => '整个课程';
  static String get playgroundScopeWeak => '薄弱内容';
  static String get playgroundModeSmartMix => '智能混合';
  static String get playgroundModeWordMatch => '单词配对';
  static String get playgroundModeQuickChoice => '极速选择';
  static String get playgroundModeListenAndPick => '听音辨义';
  static String get playgroundModeDictation => '听写挑战';
  static String get playgroundModeSentenceOrder => '句子拼图';
  static String get playgroundModeFillBlank => '填空冲刺';
  static String get playgroundModeDailyMix => '每日混合';
  static String get playgroundModeTranslation => '翻译挑战';
  static String playgroundModeCount(int count) => '$count 题';
  static String get playgroundUnavailableNoContent => '当前范围暂无可用题目';
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
  static String get playAiAssistantTitle => 'AI 助手';
  static String get playAiEngineReady => '引擎就绪';
  static String get playAiEngineNotConfigured => '未配置';
  static String get playTitle => '练习';
  static String get playDailyClose => '关闭';
  static String get playDailyTitle => '每日挑战';
  static String playDailyQuestion(int current, int total) =>
      '第 $current 题，共 $total 题';
  static String get playDailyChallengeFallback => '每日挑战';
  static String get playDailyContinue => '继续';
  static String get playDailyGotIt => '知道了';
  static String get playDailyNoQuestions => '暂无挑战题目';
  static String get playDailyCompleteFewLessons => '先完成几节课以充实题库。';
  static String get playWeakWordsEmptyHint =>
      '过去 30 天内错过两次的单词会出现在这里。';
  static String get playWeakWordsTitleAppBar => '薄弱单词';

  // ── Play Hub 重构（今日复习 Hero + 复习队列 + 长按浮窗） ──
  static String get playTodayHeroTitle => '开始今日复习';
  static String get playTodayHeroAllClear => '今日队列已清空，随便练练吧';
  static String playTodayHeroNext(String label) => '接下来：$label';
  static String get playTodayHeroTotalLabel => '项待复习';
  static String get playQueueSectionTitle => '复习队列';
  static String get playPracticeToolsTitle => '练习工具';
  static String get playLongPressHint => '长按查看数据详情';
  static String get playQueueChipMistake => '错题';
  static String get playQueueChipWords => '单词';
  static String get playQueueChipGrammar => '语法';
  static String get playQueueChipAnki => 'Anki';

  // 浮窗通用
  static String get playPopupEnter => '进入';
  static String get playPopupToday => '今天';
  static String get playPopupYesterday => '昨天';
  static String playPopupDaysAgo(int days) => '$days 天前';

  // 今日队列浮窗
  static String get playPopupNextQueueLabel => '下一个';

  // 错题浮窗
  static String get playPopupMistakePending => '待复习错题';
  static String get playPopupMistakeGrammar => '语法类错题';
  static String get playPopupMistakeRewrite => '待重写';
  static String get playPopupRecentMistakes => '最近错题';

  // 单词复习浮窗
  static String get playPopupSrsWords => '待复习单词';
  static String get playPopupSrsExpressions => '待复习表达';
  static String get playPopupSrsSeen => '已进入复习';
  static String get playPopupSrsRegistered => '已登记';
  static String get playPopupSrsLapse => '高频遗忘';

  // 语法浮窗
  static String get playPopupGrammarDue => '待复习语法';
  static String get playPopupGrammarSeen => '已进入复习';
  static String get playPopupGrammarRegistered => '已登记';

  // Anki 浮窗
  static String get playPopupAnkiTotal => '合计待复习';
  static String get playPopupAnkiLegacy => '导入牌组';
  static String get playPopupAnkiOfficial => 'Official 牌组';
  static String get playPopupAnkiUnavailable => '同步不可用，计数可能过期';

  // 薄弱单词浮窗
  static String get playPopupWeakSourceHint => '近 30 天错题聚合 · 错过两次起计';
  static String playPopupWeakTimes(int count) => '错 $count 次';

  // 复习进度浮窗
  static String get playPopupRecent7Days => '近 7 天复习';
  static String get playPopupTotalReviews => '累计复习';
  static String get playPopupStudyMinutes => '累计学习';
  static String playPopupMinutesValue(int minutes) => '$minutes 分钟';
  static String get playPopupNoStatsYet => '暂无统计数据';

  // AI 浮窗
  static String get playPopupAiEngine => 'AI 引擎';
  static String get playPopupAiProvider => '服务商';
  static String get playPopupAiModel => '模型';
  static String get playPopupAiNotReadyHint => '配置 API Key 后可使用讲解与诊断';

  // ── Review ──
  static String get reviewContinueUpper => '继续';
  static String get reviewGotItUpper => '知道了';
  static String get reviewWeakWordsTitleAppBar => '薄弱单词';
  static String get reviewDoYouKnow => '你记得这个内容吗？';
  static String get reviewDontKnow => '不记得';
  static String get reviewKnowIt => '记得';
  static String get reviewBinaryForgotten => '不记得';
  static String get reviewBinaryRemembered => '记得';
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
  static String get reviewMistakeEmptyTitle => '暂无错题可复习';
  static String get reviewMistakeEmptyHint =>
      '错题会自动记录在此处；每次最多练习 10 个。';
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
  static String get reviewMistakeFilterAll => '全部';
  static String reviewRewriteProgress(int count, int goal) =>
      '已重写 $count / $goal 次，再答对 ${goal - count} 次自动移除';
  static String timeAgo(DateTime time, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final diff = current.difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays <= 7) return '${diff.inDays}天前';
    final yearPrefix = time.year == current.year ? '' : '${time.year}年';
    return '$yearPrefix${time.month}月${time.day}日';
  }

  // ── Mistake dashboard (错题仪表盘) ──
  static String get mistakeDashboardTitle => '错题仪表盘';
  static String get mistakeDashboardActiveLabel => '活跃错题';
  static String get mistakeDashboardMasteredLabel => '累计已攻克';
  static String get mistakeDashboardConsolidateLabel => '待巩固';
  static String get mistakeDashboardTrendTitle => '近14天错题趋势';
  static String get mistakeDashboardTrendEmpty => '近14天暂无新错题，保持！';
  static String mistakeDashboardTrendSummary(int days, int total) =>
      '近14天有 $days 天出现新错题，共 $total 个';
  static String get mistakeDashboardDistributionTitle => '类型分布';
  static String get mistakeDashboardOtherType => '其他';
  static String get mistakeDashboardFrequentTitle => '高频错题';
  static String mistakeDashboardTimes(int count) => '$count 次';
  static String get mistakeDashboardOldestTitle => '最久未攻克';
  static String get mistakeDashboardEmptyTitle => '暂无错题数据';
  static String get mistakeDashboardEmptyMessage => '答题产生的错题统计会出现在这里。';
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
  static String get lessonAnkiRedoFlushFailed =>
      '提前复习未能全部写入 Anki。请到 Anki 复习里再过一遍这些卡片。';
  static String get lessonCorrect => '正确';
  static String get lessonWrong => '错误';
  static String get lessonTime => '用时';
  static String get lessonXp => '经验值';
  static String get lessonAnswerBreakdown => '答题明细';
  static String lessonResultsCount(int correctCount, int totalCount) =>
      '$correctCount / $totalCount';
  static String get lessonBackToCourses => '返回课程';
  static String get lessonAccuracy => '正确率';
  static String lessonPercentValue(int percent) => '$percent%';
  static String lessonQuestionResult(int index, String prompt) =>
      '$index. $prompt';
  static String lessonQuestionAnswer(String correctAnswer) =>
      '答案：$correctAnswer';
  static String get lessonNotYet => '还未通过';
  static String lessonMasteryMessage(
          int correct, int total, int accuracyPercent) =>
      '你答对 $correct / $total（$accuracyPercent%）。需要 80% 才能通过。再试一次！';
  static String get lessonTryAgain => '再试一次';
  static String lessonDurationSeconds(int seconds) => '$seconds秒';
  static String lessonDurationMinutes(int minutes, int seconds) =>
      '$minutes分$seconds秒';
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
  static String get aiDepthGrammarPointLabel => '语法点';
  static String get aiDepthSynonymWordsLabel => '要辨析的词（逗号分隔）';
  static String get aiDepthGenerate => '生成';
  static String get aiDepthCopy => '复制';
  static String get aiDepthCopied => '已复制';
  static String aiDepthError(Object error) => '出错了：$error';
  static String get aiDepthRelatedExamples => '相关例句';
  static String get aiDepthContrastWith => '易混淆';
  static String get aiDepthNuance => '差异';
  static String get aiDepthWhenToUseA => '用 A 的场景';
  static String get aiDepthWhenToUseB => '用 B 的场景';
  static String get aiDepthStructure => '句型';

  // ── AI companion errors (unified) ──
  static String get aiErrorNotConfigured => '请先配置 AI API';
  static String get aiErrorNetwork => '网络异常，请检查连接';
  static String get aiErrorTimeout => '响应超时，请重试或换模型';
  static String get aiErrorUnauthorized => '密钥无效或无权限';
  static String get aiErrorRateLimited => '请求过于频繁或额度不足';
  static String get aiErrorCancelled => '已停止生成';
  static String get aiErrorParseFailed => '模型返回格式异常，请重试';
  static String get aiErrorUnknown => 'AI 请求失败，请稍后重试';
  static String get aiStopGenerating => '停止';
  static String get aiDisclaimer => 'AI 可能有误，请以课程与词典为准';
  static String get aiNotConfiguredBody => '配置 AI 后即可使用伴学功能';
  static String get aiNotConfiguredCta => '去配置';
  static String get aiSaveExplanation => '收藏讲解';
  static String get aiExplanationSaved => '已收藏';
  static String get aiRetry => '重试';

  // ── AI explain prefs ──
  static String get aiPrefsSectionTitle => '讲解偏好';
  static String get aiPrefsReplyLanguage => '回复语言';
  static String get aiPrefsReplyZh => '中文';
  static String get aiPrefsReplyEn => '英文';
  static String get aiPrefsReplyTarget => '目标语';
  static String get aiPrefsDepth => '讲解深度';
  static String get aiPrefsDepthBrief => '简略';
  static String get aiPrefsDepthStandard => '标准';
  static String get aiPrefsDepthDetailed => '详细';
  static String get aiPrefsAllowReveal => '允许最终揭示答案';
  static String get aiPrefsInjectContext => '注入学习数据（错题/弱词）';

  // ── Free tutor chat ──
  static String get aiTutorChatTitle => '自由问答';
  static String get aiTutorChatModeQa => '答疑';
  static String get aiTutorChatModeSentence => '造句批改';
  static String get aiTutorChatModeRoleplay => '情景对话';
  static String get aiTutorChatEmpty => '随便问语法、用法或造句。不会生成课程。';
  static String get aiTutorChatHint => '输入你的问题…';
  static String get aiTutorNewSession => '新会话';
  static String get aiRoleplayDining => '点餐';
  static String get aiRoleplayDirections => '问路';
  static String get aiRoleplayIntro => '自我介绍';
  static String get aiRoleplayShopping => '购物';

  // ── Diagnosis ──
  static String get aiDiagnosisTitle => '学习诊断';
  static String get aiDiagnosisGenerate => '生成诊断报告';
  static String get aiDiagnosisEmpty => '先积累一些错题或弱词，再来生成文字诊断。';
  static String get aiDiagnosisWeakAreas => '薄弱点';
  static String get aiDiagnosisTips => '优先建议';
  static String get aiDiagnosisDrills => '可练想法';
  static String get aiDiagnosisRateLimited => '请稍后再生成（约 1 分钟内限一次）';
  static String get aiDiagnosisSecondaryCta => '用这些薄弱点生成练习课';

  // ── Dictionary AI ──
  static String get aiDictEnrich => 'AI 扩展';
  static String get aiDictExamples => '例句';
  static String get aiDictMnemonic => '记忆钩';
  static String get aiDictEnriching => '正在生成扩展…';

  // ── Saved explanations ──
  static String get aiSavedListTitle => '收藏的讲解';
  static String get aiSavedListEmpty => '还没有收藏。在讲解气泡或深度卡上点收藏即可。';
  static String get aiSavedSearchHint => '搜索标题或正文…';
  static String get aiSavedDelete => '删除';

  // ── Review companion ──
  static String get aiExplainCard => '讲讲这张';
  static String get aiExplainCardTitle => '卡片讲解';
  static String get aiExplainCardDisclaimer => '解释仅供理解，以卡片答案为准。';

  // ── Mistake / weak one-tap ──
  static String get aiExplainWeakWord => 'AI 讲解';

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

  // ── AI Hub (Phase 2.3 + companion) ──
  static String get commonNavAiHub => 'AI';
  static String get aiHubTitle => 'AI Hub';
  static String get aiHubHeroReconfigure => '重新配置';
  static String get aiHubHeroIncomplete => '请先填写 API Key + Base URL + 模型';
  static String get aiHubContinue => '继续';
  static String get aiHubContinueEmpty => '完成一次 AI 讲解后会出现在这里';
  static String get aiHubNew => '开始伴学';
  static String get aiHubCompanionSection => '伴学';
  static String get aiHubAuthoringSection => '内容创作';
  static String get aiHubStartWish => '设计课程（AI）';
  static String get aiHubStartTextbook => '导入教材';
  static String get aiHubStartTutorChat => '自由问答';
  static String get aiHubStartDiagnosis => '学习诊断';
  static String get aiHubStartSaved => '收藏的讲解';
  static String get aiHubStartTutorMistakes => '按错题生成练习';
  static String get aiHubStartTutorWeak => '按弱词生成练习';
  static String get aiHubStartDepthTutor => '深度讲解';
  static String get aiHubDepthTutorSubtitleOn => '基于当前题目或手动粘贴';
  static String get aiHubDepthTutorSubtitleOff => '可打开深度讲解并粘贴句子';
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
  static String aiHubFieldCacheStats(int entries, int hits, int misses) =>
      '内存缓存: $entries 条 / 命中 $hits / 未命中 $misses';

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

  // ── AI connection page: draft save / key safety / probe classification ──
  static String get aiConfigSave => '保存';
  static String get aiConfigSaved => 'AI 连接已保存';
  static String aiConfigKeyStoredHint(String masked) => '已配置（$masked），输入新值可替换';
  static String get aiConfigBaseUrlEmpty => '请填写服务器地址';
  static String get aiConfigBaseUrlInvalid =>
      '地址格式无法识别，应形如 https://api.example.com/v1';
  static String get aiConfigBaseUrlInvalidScheme => '仅支持 http/https 地址';
  static String get aiConfigBaseUrlHttpsOnly => '正式版仅允许 https 地址（开发版可用本地 http）';
  static String get aiConfigProbeTimeout => '超时：服务器未在时限内响应';
  static String get aiConfigProbeNetwork => '网络/DNS：无法连接到服务器';
  static String get aiConfigProbeTls => 'TLS/证书：安全连接失败';
  static String get aiConfigProbeAuth => '鉴权失败：密钥无效或无权限';
  static String get aiConfigProbeRateLimit => '限流：请求过于频繁或配额不足';
  static String get aiConfigProbeModel => '模型不存在或无权访问';
  static String get aiConfigProbeFormat => '响应格式错误';
  static String get aiConfigProbeUnknown => '未知错误';
  static String get aiConfigCopyEndpoint => '复制地址';
  static String get aiConfigClearKeyButton => '清除凭据';
  static String get aiConfigClearKeyTitle => '清除 API 密钥？';
  static String get aiConfigClearKeyMessage =>
      '只删除密钥，保留服务商、模型与地址设置。清除后 AI 功能在重新配置前不可用。';
  static String get aiConfigClearKeyConfirm => '清除';
  static String get aiConfigClearKeyDone => '已清除 API 密钥';
  static String get aiConfigRestoreDefaultsButton => '恢复默认';
  static String get aiConfigRestoreDefaultsTitle => '恢复连接默认值？';
  static String get aiConfigRestoreDefaultsMessage =>
      '将服务商、模型、地址与密钥全部恢复为默认值。此操作不可撤销。';
  static String get aiConfigRestoreDefaultsConfirm => '恢复默认';
  static String get aiConfigReasoningToggle => '深度思考';
  static String get aiConfigReasoningSupportedHint =>
      '该服务商支持推理字段，开启后发送 reasoning_effort / thinking（更慢但更深思）';
  static String get aiConfigReasoningUnsupportedHint =>
      '该服务商未声明推理支持，开启会向端点发送推理字段，可能被拒绝';
  static String get aiConfigSessionKeyNotice =>
      '此平台没有持久安全存储，密钥仅本次会话有效：关闭应用后需要重新输入。密钥不会写入普通偏好。';
  static String get aiConfigMigrationPendingNotice =>
      '凭据安全迁移尚未完成，当前仍使用旧存储。重启应用会自动重试；如持续出现请在重新输入密钥前备份它。';

  // ── Anki ──
  static String get ankiImportTitle => '导入 Anki 牌组';
  static String get ankiPendingImportsTitle => '未完成的导入';
  static String get ankiImportLeaveTitle => '离开导入？';
  static String get ankiImportLeaveWait => '继续等待';
  static String get ankiImportLeaveDiscard => '放弃并清理';
  static String get ankiImportLeaveContinueLater => '稍后继续';
  static String get ankiImportLeaveBusyMessage =>
      '导入仍在进行。离开前请选择继续等待，或放弃并清理已写入的数据。';
  static String get ankiImportLeavePreviewMessage =>
      '预览尚未确认。稍后继续会保留待完成导入；放弃将回滚本次导入。';
  static String ankiPendingImportPhase(String phase) => '阶段：$phase';
  static String get ankiImportDialogTitle => '导入 Anki 牌组';
  static String get ankiImportSelectTitle => '导入 Anki 牌组';
  static String get ankiImportSelectSubtitle =>
      '从 Anki 桌面端导出牌组文件（.apkg），然后从这里导入。';
  static String get ankiChooseFile => '选择文件';
  // Wizard step labels for the new step indicator at the top of the page.
  static String get ankiStepSelect => '选择文件';
  static String get ankiStepParse => '解析中';
  static String get ankiStepPreview => '预览';
  static String get ankiStepImport => '导入中';
  static String get ankiStepDone => '完成';
  static String get ankiParsing => '正在解析 Anki 集合…';
  static String ankiImportUnavailable([String? reason]) =>
      reason == null || reason.isEmpty
          ? '当前平台或构建无法导入 Anki 牌组'
          : '当前无法导入 Anki 牌组（$reason）';

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
  // Plain-language recognition states (no confidence percentages/sources):
  // green check = auto-recognized, orange warning = worth a manual look.
  static String get ankiMappingRecognizedAuto => '将按识别结果导入';
  static String get ankiMappingNeedsCheck => '建议看一眼样卡';
  static String get ankiMappingMustFix => '请看一下样卡';
  static String get ankiMappingViewAll => '查看全部';
  static String ankiMappingSummaryAll(int typeCount) =>
      '已按内容识别 $typeCount 类卡片，一般可以直接导入。';
  static String ankiMappingSummaryNeedsCheck(int autoCount, int checkCount) =>
      '已识别 $autoCount 类；另有 $checkCount 类建议看一眼样卡（正反面是否反了）。';
  static String ankiMappingSummaryBlocking(int count) =>
      '有 $count 类卡片还分不清正面和背面，点进去看一张样卡即可。';
  static String get ankiMappingFixBlocking => '点下面红字那一行，看样卡选一下正面和背面；也可以跳过这类卡片';
  static String get ankiAdvancedOptionsTitle => '高级选项';
  static String get ankiAdvancedOptionsSummary =>
      '重复的卡自动合并 · 自动按单元分组';
  static String get ankiAiIdentify => 'AI 智能识别';
  static String get ankiAiRetry => '重新识别';
  static String get ankiAiIdentifying => 'AI 识别中…';
  static String get ankiAiNotConfiguredMessage =>
      '未配置 AI，无法智能识别。请先在「设置 > AI 工具」中配置 AI API。';
  static String get ankiAiIdentifyHint => '如未配置 AI，请先在「设置 > AI 工具」配置';
  static String get ankiNotetypeSampleFront => '正面';
  static String get ankiNotetypeSampleBack => '背面';
  static String get ankiMappingEditTitle => '看一下这类卡片';
  static String get ankiMappingFieldFront => '正面来自';
  static String get ankiMappingFieldBack => '背面来自';
  static String get ankiMappingFieldsAutoHint => '这类卡片会按原样显示，不用手动选栏。';
  static String get ankiMappingResetAuto => '恢复自动识别';
  static String get ankiMappingReason => '为什么这样认';
  static String get ankiMappingSwapSides => '交换正面和背面';
  static String get ankiMappingMoreAdjustments => '改正面 / 背面用哪一栏';
  static String get ankiMappingConfirmCorrect => '这样没问题';
  // User-facing question-type chips (import mapping): one plain label per
  // UserQuestionType — the primary interaction, replacing the internal
  // notetype mapping-type dropdown.
  static String get ankiQuestionTypeChoice => '选择题';
  static String get ankiQuestionTypeFillBlank => '填空题';
  static String get ankiQuestionTypeListen => '听力题';
  static String get ankiQuestionTypeWord => '单词卡';
  static String get ankiQuestionTypeSentence => '句子卡';
  static String get ankiQuestionTypeFlip => '翻卡片';
  static String get ankiQuestionTypeAutoSuffix => '自动';
  static String get ankiQuestionTypeSectionTitle => '学的时候做成哪种练习？';
  static String get ankiQuestionTypeSectionHint => '已按卡片内容识别，点一下就能改';
  static String get ankiMappingAdjustFields => '看样卡 / 改正面背面';
  static String ankiMappingCards(int count) => '$count 张卡片';
  static String ankiMappingSourceName(String name) => '牌组里叫「$name」';
  static String get ankiMappingEmptySample => '（可能是图片或音频）';
  static String get ankiMappingStatusRecognized => '将按下面选中的练习导入';
  static String get ankiMappingStatusAdvisory => '可以导入。若样卡正反面反了，点进去交换';
  static String get ankiMappingStatusBlocking => '点进去看样卡，选一下哪边是正面、哪边是背面';
  static String get ankiOrganizationTitle => '组织结构';
  static String get ankiOrganizationNone => '未发现单元/课时标签';
  static String get ankiOrganizationNoneDesc => '卡片将按每课 20 张分组。';
  static String get ankiSmartGrouping => '智能分组';
  // Section headers for the redesigned preview screen (3 grouped cards).
  static String get ankiPreviewSectionContent => '牌组内容';
  static String get ankiPreviewSectionContentHint => '你将导入什么';
  static String get ankiPreviewSectionMapping => '卡片会长什么样';
  static String get ankiPreviewSectionMappingHint => '按内容识别出的练习方式';
  static String get ankiPreviewStartImport => '开始导入';
  static String get ankiPreviewCancel => '取消';
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
  // Done-page headline (uses %s for card count), grouped details, and CTAs.
  static String ankiDoneSummary(int cardCount) => '$cardCount 张卡片已就绪';
  static String get ankiDoneLessonsHint => '已创建 N 节课，可立即开始学习';
  static String get ankiDoneGroupSource => '源数据';
  static String get ankiDoneGroupVocab => '词汇';
  static String get ankiDoneGroupStatus => '状态提示';
  static String get ankiDoneProgressKept => '学习进度：已保留';
  static String get ankiDoneProgressReset => '学习进度：按新卡重置';
  static String get ankiDoneViewDecks => '查看牌组';
  static String get ankiStartLearning => '立即学习';
  static String ankiCardsImported(int cardCount) => '已导入 $cardCount 张卡片';
  static String ankiLessonsCreated(int lessonCount) => '已创建 $lessonCount 节课';
  static String ankiVocabAdded(int wordEntryCount) =>
      '已添加 $wordEntryCount 个词汇条目';
  static String get ankiPickFileError => '请选择 Anki 牌组文件（.apkg）。';
  static String get ankiColpkgUnsupported =>
      '暂不支持 .colpkg 集合备份。请从 Anki 桌面端导出牌组（.apkg）后再导入。';
  static String ankiPickFileFailed(Object error) => '选择文件失败：$error';
  static String ankiParseFailed(Object error) => '解析失败：$error';
  static String get ankiPreparingImport => '正在准备导入…';
  static String get ankiImportingOfficialFirst => '正在导入到官方 Anki 集合…';
  static String get ankiOfficialPreviewBody => '牌组已读入。下面是按内容识别出的练习方式，一般可以直接导入。';
  static String get ankiOfficialMappingHint =>
      '点开可看一张样卡；叫 Basic、Vocabulary 的是牌组内部名称，可以忽略。';
  static String get ankiOfficialDedupeHint => '重复导入同一文件会自动跳过。';
  static String get ankiOfficialNeedsMapping => '还有一类卡片需要看一眼样卡，点那一行即可。';
  static String get ankiOfficialMappingConfirmed => '已确认';
  static String get ankiOfficialMappingSkipped => '已跳过';
  static String get ankiPendingImportTitle => '未完成的导入';
  static String ankiPendingImportBody(String name) =>
      '导入确认前被中断了。不能从这里接着导，放弃清理后可以重新选包。';
  static String get ankiImportSystemError => '系统错误';
  static String get ankiPendingMustDiscardBeforeNew =>
      '现在无法导入新卡片。必须先放弃这次未完成的导入。';
  static String get ankiPendingContinue => '继续';
  static String get ankiPendingDiscard => '放弃并清理';
  static String get storageOptimizeDatabase => '优化数据库';
  static String get storageOptimizeConfirmTitle => '优化数据库？';
  static String get storageOptimizeConfirmBody =>
      '会短暂占用一些磁盘空间，不会删除课程或卡片。过程中请勿强关应用。';
  static String get storageOptimizeBusy => '正在优化数据库…';
  static String storageOptimizeDone(int completed) =>
      completed <= 0 ? '优化已完成' : '优化已完成（$completed 项任务）';
  static String get storageOptimizeUnavailable =>
      '当前无法优化数据库（收藏库尚未就绪）';
  static String get storageOptimizeFailed => '优化失败，未宣称释放空间';
  static String get storageRepairCenterLink => '打开修复中心';
  static String get storageOfficialCollectionTitle => 'Anki 收藏';
  static String get storageMediaFilesTitle => '媒体文件';
  static String get storageDeleteSelected => '删除所选';
  static String get storageOfficialCollectionEmpty =>
      '还没有已导入的官方牌组。导入 .apkg 后会出现在这里。';
  static String get storageMediaFilesEmpty => '没有可管理的媒体文件夹。';
  static String get storageMediaDeleteHint =>
      '删除有对应课程的媒体时，会同时移除该牌组的卡片和学习进度，无法撤销。';
  static String get storageOwnedMediaSubtitle => '属于已导入牌组';
  static String get storageOrphanMediaSubtitle => '无对应课程的残留';
  static String get storageDeleteNothingSelected => '请先勾选要删除的项目';
  static String get storageRetiringSkipHint => '正在移除的项目已跳过';
  static String get storageForcePurgeOfficial => '强制清空残留';
  static String get storageForcePurgeOfficialHint =>
      '没有可删除的牌组，但收藏库仍占用空间。多半是卸牌组后留下的空库、检查点或临时目录。';
  static String get storageForcePurgeOfficialConfirmTitle => '强制清空 Anki 残留？';
  static String get storageForcePurgeOfficialConfirmBody =>
      '将删除无对应牌组的收藏库文件、媒体缓存、检查点和临时导入目录。已导入的牌组必须先从列表删除。此操作无法撤销。';
  static String get storageForcePurgeOfficialDone => '残留文件已清空';
  static String get storageForcePurgeOfficialBlocked =>
      '仍有已导入牌组或未完成的导入，无法强制清空';
  static String get storageForcePurgeOfficialFailed => '强制清空失败';
  static String get ankiRepairCenterTitle => 'Anki 修复中心';
  static String get ankiRepairCenterEmptyCatalog =>
      '官方收藏库尚未就绪。导入过 Anki 牌组后可在此查看待完成导入、待清理和隔离项。';
  static String get ankiRepairCenterEmpty => '没有需要处理的项目';
  static String get ankiRepairPendingCleanup => '待清理';
  static String get ankiRepairQuarantined => '已隔离';
  static String get ankiRepairDeleteQuarantine => '删除';
  static String get ankiRepairDeleteQuarantineConfirmTitle => '删除隔离数据？';
  static String get ankiRepairDeleteQuarantineConfirmBody =>
      '将删除该来源的卡片、复习进度和媒体。此操作无法撤销。';
  static String get ankiRepairMaintenanceJobs => '维护任务';
  static String get ankiRepairFailedJobs => '最近失败的维护';
  static String get ankiRepairOrphans => '无登记残留';
  static String get ankiRepairRetryCleanup => '重试清理';
  static String get ankiRepairExportDiagnostics => '导出诊断';
  static String get ankiRepairExportCopied => '已复制诊断摘要（不含密钥）';
  static String get ankiRepairDiscardConfirmTitle => '放弃并清理？';
  static String get ankiRepairDiscardConfirmBody =>
      '将取消这次未完成的导入并清理临时文件，不会删除已确认的课程。';
  static String get ankiRepairRetryCleanupConfirmTitle => '重试清理？';
  static String get ankiRepairRetryCleanupConfirmBody =>
      '将再次尝试删除该来源在集合中的卡片与登记。已确认的其他课程不受影响。';
  static String get ankiRepairActionUnavailable => '当前无法执行该操作';
  static String ankiRepairSourceState(String state) {
    switch (state) {
      case 'pending_cleanup':
        return '等待清理';
      case 'retiring':
        return '正在从收藏中移除';
      case 'quarantined':
        return '已隔离，需要处理';
      case 'active':
        return '使用中';
      default:
        return state;
    }
  }

  static String ankiRepairJobKind(String kind) {
    switch (kind) {
      case 'media_gc':
        return '清理无用媒体';
      case 'metadata_prune':
        return '清理过期元数据';
      case 'compact_collection':
        return '压缩收藏库';
      case 'compact_catalog':
        return '压缩目录库';
      case 'compact_course':
        return '压缩课程库';
      case 'v2_source_delete':
        return '移除牌组';
      case 'v2_view_rebuild':
        return '重建课程视图';
      default:
        return kind;
    }
  }

  static String ankiRepairJobState(String state) {
    switch (state) {
      case 'pending':
        return '排队中';
      case 'running':
        return '进行中';
      case 'retry_wait':
        return '等待重试';
      case 'failed':
        return '失败';
      case 'completed':
        return '已完成';
      default:
        return state;
    }
  }
  static String get ankiOfficialMappingSuggested => '推荐';
  // Exercise-kind presets on the official mapping page: which practice to
  // generate from this notetype (writes suggestion.enabledKinds).
  static String get ankiOfficialExerciseTitle => '学的时候做成哪种练习？';
  static String get ankiOfficialExerciseHint => '已按内容选择，多数情况不用改';
  static String get ankiOfficialExerciseAuto => '按卡片原样';
  static String get ankiOfficialExerciseChoice => '选择题';
  static String get ankiOfficialExerciseFillBlank => '填空题';
  static String get ankiOfficialExerciseListen => '听力题';
  static String get ankiOfficialExerciseFlip => '翻卡片';
  static String get ankiOfficialExerciseClozeNote => '样卡带挖空，会做成填空题';
  static String get ankiAssemblingCourse => '正在构建课程树…';
  static String get ankiMigratingSrs => '正在迁移 SRS 状态…';
  static String get ankiCopyingMedia => '正在复制媒体文件…';
  static String get ankiSavingMetadata => '正在保存导入元数据…';
  static String ankiImportFailed(Object error) => '导入失败：$error';
  static String get ankiReviewTitle => 'Anki 复习';
  static String get ankiNoCardsDue => '暂无待复习的 Anki 卡片。';
  static String get ankiFormalReviewEmptyHint =>
      '先完成课程里的一课，该课的卡片才会进入 Anki 复习。有导入历史的卡片可直接复习。';
  static String get ankiReviewPreparing => '正在准备本批卡片…';
  static String get ankiReviewLoadFailed => '加载复习卡片失败';
  static String ankiReviewLoadFailedDetail(Object error) => '加载失败：$error';
  static String get ankiReviewRetry => '重试';
  static String get ankiReviewScreenTitle => 'Anki 复习';
  static String get ankiImportNewDeck => '导入新牌组';
  static String ankiCardsDueReview(int totalDue) => '$totalDue 张卡片待复习';
  static String ankiFormalDueBreakdown({
    required int introducedDue,
    required int unintroducedNew,
  }) =>
      '已学待复习 $introducedDue 张 · 未学新卡 $unintroducedNew 张';
  static String get ankiDueUnavailable => '到期数量暂不可用，请稍后刷新';
  static String get ankiReviewAll => '开始复习';
  static String get ankiHubDecksTitle => '牌组';
  static String get ankiHubCaughtUpTitle => '今日已清完';
  static String get ankiHubCaughtUpMessage => '没有到期卡片。先完成课程里的一课，或浏览已导入的牌组。';
  static String get ankiHubDueCountLabel => '待复习';
  static String get ankiBrowseCards => '浏览卡片';
  static String get ankiDeckStats => '统计';
  static String get ankiPinDeck => '置顶';
  static String get ankiDeckOptions => '牌组设置';
  static String get ankiCardRedo => '重做';
  static String get ankiCardBury => '搁置';
  static String get ankiCardSuspend => '暂停';
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
  /// 批量移除的部分成功文案：`uninstall` 返回 false（locator 未就绪，
  /// 什么都没发生）与抛错（提交前失败）都按「未完成」计数——v2 删除
  /// 序列里用户可见的移除在账本 COMMIT 即生效，之后的清理失败不再
  /// 归入此列。
  static String ankiDeckRemovalPartial(int completed, int failed) =>
      '已移除 $completed 项，$failed 项未完成，请稍后重试';
  static String get ankiDeckRemovalFailed => '牌组移除未完成，请稍后重试';
  static String get ankiShowAnswer => '显示答案';
  static String get ankiShowAnswerFlip => '显示答案 / 翻面';
  static String get ankiBuryCard => '暂缓卡片';
  static String get ankiBurySiblings => '暂缓同源卡片';
  static String get ankiSuspendCard => '暂停卡片';
  static String get ankiFilteredDeckBuryUnsupported => '筛选牌组不支持暂缓/暂停卡片。';
  static String get ankiToggleSurfaceWebView => '切换至原版 WebView';
  static String get ankiToggleSurfacePractice => '切换至课化卡片';
  static String get ankiToggleSurfaceFidelityOnly => '该卡片含复杂排版或脚本，仅支持官方原版渲染';
  static String get ankiChooseCorrectAnswer => '请选择正确答案';
  static String get ankiAnswerExplanation => '答案解析：';
  static String get ankiClozeAnswer => '填空答案：';
  static String get ankiListenAudio => '播放音频';
  static String get ankiAudioMissing => '音频缺失';
  static String get ankiFileReadFailed => '无法读取该文件';
  static String get ankiCorruptDeck => '文件已损坏或不是有效的 Anki 牌组';
  static String get anki21bTreeDeferred => '已导入官方牌组；练习课稍后再生成';
  static String get ankiImportFailedHuman => '导入失败，请重试';
  static String get ankiRecognitionBandReview => '建议确认';
  static String get ankiRecognitionBandFallback => '需确认';
  static String get ankiFieldRolePrompt => '正面';
  static String get ankiFieldRoleResponse => '背面';
  static String get ankiFieldRoleOptions => '选项';
  static String get ankiFieldRoleAudio => '音频';
  static String get ankiFieldRoleImage => '图片';
  static String get ankiFieldRolePronunciation => '读音';
  static String get ankiFieldRoleExample => '例句';
  static String get ankiFieldRoleHint => '提示';
  static String get ankiFieldRoleExtra => '补充';
  static String get ankiFieldRoleUnit => '单元';
  static String get ankiFieldRoleLesson => '课时';
  static String get ankiFieldRoleIgnored => '未用';
  static String get ankiFieldNameFront => '正面';
  static String get ankiFieldNameBack => '背面';
  static String get ankiFieldNameText => '正文';
  static String get ankiFieldNameExtra => '补充';
  static String get ankiFieldNameOcclusion => '遮挡图';
  static String get ankiFieldNameImage => '图片';
  static String get ankiFieldNameAudio => '音频';
  static String get ankiAdvancedFidelityTitle => 'Anki 保真 / 解密（仅旧版导入源）';
  static String get ankiAdvancedFidelitySubtitle => '仅旧版导入源生效';

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
  static String coursesDueLessons(int count) => '$count 项待复习';
  static String coursesWeakLessons(int count) => '$count 项需加强';
  static String get coursesNextLesson => '下一课';
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
  static String get profileLearningStatsTitle => '学习统计';
  static String get profileTodayTitle => '今日概览';
  static String get profileStatsEntrySubtitle => '近 7 天经验、总量与 Anki';
  // ── Achievements v2 (成就系统焕新) ──
  static String profileAchievementsBadgeCount(int unlocked, int total) =>
      '已获得 $unlocked/$total 枚徽章';
  static String profileAchievementsNearComplete(int count) => '$count 项接近完成';
  static String get achievementsOverviewTitle => '徽章收藏';
  static String achievementsOverviewCount(int unlocked, int total) =>
      '已获得 $unlocked / $total 枚徽章';
  static String achievementsCompletionRatio(int percent) => '完成度 $percent%';
  static String get achievementsNearestSection => '距离最近';
  static String get achievementsFilterAll => '全部';
  static String get achievementsFilterInProgress => '进行中';
  static String get achievementsFilterUnlocked => '已获得';
  static String get achievementsRecentSection => '最近获得';
  static String get achievementsRecentEmpty => '完成第一课或第一次复习，即可获得第一枚徽章';
  static String get achievementsMigrationBackfillTag => '历史补记';
  static String get achievementsNewBadgeTag => 'NEW';
  static String achievementsTierProgress(int current, int target) =>
      '$current / $target';
  static String achievementsTierCompleted(int count, int total) =>
      '$count/$total';
  static String get achievementsStateLocked => '未解锁';
  static String get achievementsStateInProgress => '进行中';
  static String get achievementsStateUnlocked => '已获得';
  static String get achievementsStateMaxed => '已满级';
  static String achievementsRemainingCourses(int count) => '再完成 $count 课';
  static String achievementsRemainingPerfects(int count) => '再完美完成 $count 课';
  static String achievementsRemainingStreakDays(int count) => '再坚持 $count 天';
  static String achievementsRemainingXp(int count) => '再获得 $count XP';
  static String achievementsRemainingDailyXp(int count) => '单日再获得 $count XP';
  static String achievementsRemainingReviews(int count) => '再复习 $count 张卡片';
  static String achievementsRemainingWords(int count) => '再学习 $count 个词条';
  static String get achievementsDetailTierLadder => '完整阶梯';
  static String get achievementsDetailUnlockedOn => '解锁于';
  static String get achievementsDetailNextStep => '下一步';
  static String get achievementsDetailFinalReward => '终阶纪念';
  static String get achievementsDetailStory => '系列故事';
  static String get achievementsCosmeticTitleFarWalker => '称号「远行者」';
  static String get achievementsCosmeticTitleHundredFlawless => '称号「百课无瑕」';
  static String get achievementsCosmeticStreak365 => '365 天纪念头像环';
  static String get achievementsCosmeticPreviewSuffix => ' + 专属纪念';
  static String get achievementsUnlockBannerTitle => '新成就解锁';
  static String achievementsUnlockBannerCount(int count) => '本次获得 $count 枚徽章';
  static String get achievementsUnlockBannerViewAll => '查看成就';
  static String get achievementsFunPreviewBanner => '预览全部（Fun Lab，非真实解锁）';
  static String get achievementsFunPreviewTag => '预览';
  static String get achievementsGemRewardSuffix => '宝石';
  // 系列名称与描述（key = seriesId）
  static String get achievementsSeriesCourseJourney => '课程行者';
  static String get achievementsSeriesCourseJourneyDesc => '累计完成不重复的课程';
  static String get achievementsSeriesPerfectJourney => '完美主义者';
  static String get achievementsSeriesPerfectJourneyDesc => '零失误完成课程，收集无瑕印记';
  static String get achievementsSeriesStreakJourney => '烈焰不息';
  static String get achievementsSeriesStreakJourneyDesc => '连续学习，让火焰持续燃烧';
  static String get achievementsSeriesXpJourney => '经验积累';
  static String get achievementsSeriesXpJourneyDesc => '累计获得的经验值';
  static String get achievementsSeriesDailyFocus => '今日专注';
  static String get achievementsSeriesDailyFocusDesc => '单日获得的最高经验值';
  static String get achievementsSeriesReviewJourney => '复习达人';
  static String get achievementsSeriesReviewJourneyDesc => '累计提交的复习卡片作答';
  static String get achievementsSeriesVocabularyJourney => '词海拾贝';
  static String get achievementsSeriesVocabularyJourneyDesc => '学习过的唯一词条';
  // 进度单位
  static String get achievementsUnitLessons => '课';
  static String get achievementsUnitDays => '天';
  static String get achievementsUnitXp => 'XP';
  static String get achievementsUnitCards => '张';
  static String get achievementsUnitWords => '词';
  static String get achievementsPersonalBest => '个人最高纪录';
  static String get profileXpToday => '今日经验';
  static String get profileStudyTime => '学习时长';
  static String get profileAccuracy => '正确率';
  static String profileStudyTimeValue(int minutes) => '$minutes分';
  static String profileAccuracyValue(int accuracy) => '$accuracy%';
  static String get profileLast7Days => '最近 7 天';
  static String get profileTotalStudyTime => '总学习时长';
  static String get profileOverallAccuracy => '总正确率';
  static String get profileLessonsDone => '完成课程';
  static String get profileReviewsDone => '复习次数';
  // ── Review progress ──
  static String get reviewProgressTitle => '复习进度';
  static String get reviewProgressSubtitle => '学习与复习统计、筛选与记忆曲线';

  // ── Review dashboard home (Plan 3 §15.1) ──
  static String get reviewDashboardTitle => '复习概览';
  static String get reviewInsightsTitle => '学习洞察';
  static String get reviewOpenInsights => '查看学习洞察';
  static String get reviewTodayTitle => '今日复习';
  static String get reviewContinueCta => '继续复习';
  static String get reviewTodayDoneCta => '今日已完成';
  static String reviewTodayGoalProgress(int xp, int goal) => '$xp / $goal XP';
  static String reviewTodayReviewed(int count) => '已复习 $count 张';
  static String reviewMonthDay(int day) => '$day 日';
  static String get reviewDueCard => '待复习';
  static String get reviewNewCard => '新卡';
  static String get reviewOverdueCard => '逾期';
  static String reviewStreakDays(int days) => '连续学习 $days 天';
  static String reviewThisWeek(int days) => '本周 $days / 7 天';
  static String reviewSevenDaySummary(int activeDays, int total) =>
      '最近 7 天学习 $activeDays 天，共复习 $total 张';
  static String reviewTodayMinutes(int minutes) => '学习 $minutes 分钟';
  static String reviewAccuracyPct(int pct) => '准确率 $pct%';
  static String get reviewNoDataYet => '暂无数据';
  static String get reviewSourcesTitle => '课程与牌组';
  static String reviewSourceDue(int count) => '$count 待复习';
  static String get reviewEmptyHint => '还没有卡片。导入课程或 Anki 牌组后开始学习。';
  static String get reviewRefreshFailedKeptOld => '刷新失败，正在显示上一次的数据。';
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
  static String get reviewProgressRangeAll => '全部';
  static String get reviewProgressRange7 => '7天';
  static String get reviewProgressRange30 => '30天';
  static String get reviewProgressRange90 => '90天';
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
  static String profileRetentionValue(int retention) => '$retention%';
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
  static String srsPreviewKnown(int days) => '认识 · 约 $days天';
  static String get srsPreviewUnknown => '不认识 · 10 分钟';
  static String profileTotalStudyTimeValue(int totalMinutes) =>
      '$totalMinutes分';
  static String profileOverallAccuracyValue(int accuracy) => '$accuracy%';
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
  static String get settingsFunSnapshotSection => '实验存档';
  static String get settingsFunActionsSection => '实验功能';
  static String get settingsFunSnapshotStatusTitle => '当前检查点';
  static String get settingsFunSnapshotLoading => '正在读取…';
  static String get settingsFunSnapshotEmpty => '尚未创建，危险操作暂不可用';
  static String settingsFunSnapshotReady(String time, int count) =>
      '$time · $count 个复习项目';
  static String get settingsFunSnapshotCreateTitle => '创建实验存档';
  static String get settingsFunSnapshotCreateSubtitle => '保存当前学习进度，之后可一键恢复';
  static String get settingsFunSnapshotReplaceTitle => '替换实验存档';
  static String get settingsFunSnapshotReplaceSubtitle => '用当前学习进度覆盖已有检查点';
  static String get settingsFunSnapshotCreateDialogTitle => '创建实验存档？';
  static String get settingsFunSnapshotCreateDialogMessage =>
      '将保存当前复习状态、历史、分数、宝石、课程进度、错题和学习统计。课程内容与应用设置不会保存。';
  static String get settingsFunSnapshotReplaceDialogTitle => '替换现有存档？';
  static String get settingsFunSnapshotReplaceDialogMessage =>
      '旧检查点会被当前学习进度覆盖，此操作无法撤销。';
  static String get settingsFunSnapshotCreateConfirm => '创建存档';
  static String get settingsFunSnapshotReplaceConfirm => '替换存档';
  static String get settingsFunSnapshotCreated => '📦 实验存档已创建';
  static String get settingsFunSnapshotRestoreTitle => '恢复实验存档';
  static String get settingsFunSnapshotRestoreSubtitle => '恢复完整学习进度，存档本身会继续保留';
  static String get settingsFunSnapshotRestoreDialogTitle => '恢复实验存档？';
  static String get settingsFunSnapshotRestoreDialogMessage =>
      '当前学习进度将被检查点覆盖。恢复后仍可再次使用这个检查点。';
  static String get settingsFunSnapshotRestoreConfirm => '恢复';
  static String get settingsFunSnapshotRestored => '↩️ 学习进度已恢复';
  static String get settingsFunSnapshotDeleteTitle => '删除实验存档';
  static String get settingsFunSnapshotDeleteSubtitle => '删除后危险操作将再次锁定';
  static String get settingsFunSnapshotDeleteDialogTitle => '删除实验存档？';
  static String get settingsFunSnapshotDeleteDialogMessage =>
      '删除检查点不会改变当前学习进度，但之后将无法恢复到该状态。';
  static String get settingsFunSnapshotDeleteConfirm => '删除';
  static String get settingsFunSnapshotDeleted => '实验存档已删除';
  static String get settingsFunSnapshotRequiredTitle => '需要实验存档';
  static String get settingsFunSnapshotRequiredMessage =>
      '请先创建实验存档，再使用会修改学习进度的功能。';
  static String get settingsFunSnapshotContentChanged =>
      '课程内容或 Anki 导入已发生变化，无法安全恢复。请删除并重新创建实验存档。';
  static String settingsFunOperationFailed(Object error) => '操作失败：$error';
  static String get settingsFunPostponeTitle => '复习时间机器';
  static String get settingsFunPostponeSubtitle => '将全部有效复习内容推迟 1 天';
  static String get settingsFunPostponeDialogTitle => '推迟全部复习？';
  static String settingsFunPostponeDialogMessage(int count) =>
      '将 $count 个词汇、表达、语法或 Anki 复习计划统一顺延 24 小时。暂停和埋藏卡片不会改变。';
  static String get settingsFunPostponeConfirm => '推迟 1 天';
  static String settingsFunPostponeDone(int count) => '⏰ 已将 $count 个复习计划推迟 1 天';
  static String get settingsFunAutoAnswerTitle => '破解版（自动出答案）';
  static String get settingsFunAutoAnswerSubtitle => '上课时自动选择正确答案并提交';
  static String get settingsFunAutoAnswerOn => '🎮 破解模式已开启 — 上课时将自动答题';
  static String get settingsFunAutoAnswerOff => '破解模式已关闭';
  static String get settingsFunMaxScoreTitle => '一键满级';
  static String get settingsFunMaxScoreSubtitle => '将总分设为 99999';
  static String get settingsFunMaxScoreDialogTitle => '一键满级？';
  static String get settingsFunMaxScoreDialogMessage =>
      '你的真实分数将被覆盖为 99999，可通过实验存档恢复。';
  static String get settingsFunMaxScoreConfirm => '满级';
  static String get settingsFunMaxScoreDone => '⭐ 总分已设为 99999';
  static String get settingsFunMaxGemsTitle => '无限宝石';
  static String get settingsFunMaxGemsSubtitle => '将宝石设为 99999';
  static String get settingsFunMaxGemsDialogTitle => '无限宝石？';
  static String get settingsFunMaxGemsDialogMessage =>
      '你的真实宝石数将被覆盖为 99999，可通过实验存档恢复。';
  static String get settingsFunMaxGemsConfirm => '无限宝石';
  static String get settingsFunMaxGemsDone => '💎 宝石已设为 99999';
  static String get settingsFunAllAchievementsTitle => '全成就解锁';
  static String get settingsFunAllAchievementsSubtitle => '解锁所有成就';
  static String get settingsFunAllAchievementsDialogTitle => '全成就解锁？';
  static String get settingsFunAllAchievementsDialogMessage =>
      '个人页将把所有成就显示为满级，但不会修改真实学习统计。';
  static String get settingsFunAllAchievementsConfirm => '解锁';
  static String get settingsFunAllAchievementsDone => '🏆 所有成就已解锁';

  // ── Anki sample ──
  static String get ankiSampleDeckName => '示例 · 土耳其语问候';
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

  // ── Official Anki errors ──
  static String get officialAnkiRetryCurrentSide => '重试当前面';
  static String get officialAnkiErrorFallback => '官方卡片暂时无法显示，请重试。';
  static String get officialAnkiCanonicalFlipHint => '先翻面查看答案后继续';
  static String get officialAnkiCanonicalViewed => '已查看原卡';

  /// Localize an `official_anki.*` message key emitted by the native bridge
  /// or the Dart engine layer. Unknown keys resolve to a generic user-facing
  /// message — the raw key is a diagnostic, never UI copy (it used to leak
  /// into release error screens as `官方卡片无法显示（official_anki.x）`).
  static String officialAnkiError(String key) {
    switch (key) {
      case 'official_anki.card_not_found':
        return '这张官方卡片不存在。';
      case 'official_anki.unrenderable_card':
        return '该卡片模板不可渲染或已损坏，可手动跳过或搁置。';
      case 'official_anki.render_failed':
        return '官方模板渲染失败。';
      case 'official_anki.renderer_flag_fail_closed':
        return '官方原卡渲染未启用。';
      case 'official_anki.worker_required':
        return '官方渲染需要独立 worker，当前不可用。';
      case 'official_anki.worker_init_failed':
        return '官方引擎启动失败，请重试。';
      case 'official_anki.worker_rpc_timeout':
        return '官方引擎响应超时，请重试。';
      case 'official_anki.in_process_forbidden':
        return '生产路径禁止使用进程内回退。';
      case 'official_anki.flag_fail_closed':
        return '官方 Anki 功能未打开。';
      case 'official_anki.review_fail_closed':
        return '官方复习暂时不可用，请稍后再试。';
      case 'official_anki.scheduler_flag_fail_closed':
        return '官方复习调度未启用。';
      case 'official_anki.scheduler_busy':
        return '官方引擎正忙，请稍后重试。';
      case 'official_anki.scheduler_capability_missing':
        return '当前 native 引擎缺少该能力，需要重新构建。';
      case 'official_anki.capability_missing':
        return '当前 native 引擎缺少所需能力，需要重新构建 libturna_anki.so。';
      case 'official_anki.internal_error':
      case 'official_anki.backend_error':
      case 'official_anki.transport_error':
        return '官方复习遇到内部错误。';
      case 'official_anki.answer_commit_unknown':
        return '官方评分结果未确认，正在等待核对。';
      case 'official_anki.answer_failed':
        return '官方评分失败，请重试。';
      case 'official_anki.scheduling_context_stale':
      case 'official_anki.page_token_stale':
        return '官方复习上下文已过期，请重试。';
      case 'official_anki.queue_empty':
        return '当前没有待复习的官方卡片。';
      case 'official_anki.invalid_review_state':
      case 'official_anki.invalid_state':
      case 'official_anki.review_session_disposed':
      case 'official_anki.engine_disposed':
        return '官方复习状态无效，请重新开始。';
      case 'official_anki.invalid_bury_action':
        return '官方搁置或暂停操作无效。';
      case 'official_anki.filtered_deck_unsupported':
        return '当前过滤牌组不支持搁置或暂停。';
      case 'official_anki.contract_decode_failed':
      case 'official_anki.contract_version_mismatch':
      case 'official_anki.invalid_envelope':
      case 'official_anki.empty_payload':
        return '官方复习数据不完整。';
      case 'official_anki.write_owner_denied':
        return '该复习路径不允许写入。';
      case 'official_anki.operation_conflict':
        return '官方复习正在进行，不能同时导入或重开牌组。';
      case 'official_anki.collection_already_open':
        return '官方 Collection 已打开，请重试。';
      case 'official_anki.collection_locked':
        return '官方 Collection 被占用，请稍后重试。';
      case 'official_anki.collection_open_failed':
      case 'official_anki.collection_corrupt':
        return '官方 Collection 打开失败或已损坏。';
      case 'official_anki.library_missing':
      case 'official_anki.symbol_missing':
      case 'official_anki.library_open_failed':
        return '官方 Anki 核心库缺失或不可用。';
      case 'official_anki.io_error':
        return '读写官方数据时出错。';
      case 'official_anki.import_cancelled':
        return '导入已取消。';
      case 'official_anki.package_invalid':
      case 'official_anki.package_not_found':
        return '牌组文件无效或不存在。';
      case 'official_anki.deck_not_found':
        return '官方牌组不存在。';
      case 'official_anki.undo_unavailable':
        return '当前没有可撤销的操作。';
      case 'official_anki.redo_unavailable':
        return '当前没有可重做的操作。';
      case 'official_anki.unknown_migration_state':
        return '未知的 Legacy 迁移状态。';
      case 'official_anki.illegal_migration_transition':
        return 'Legacy 迁移状态不能这样切换。';
      case 'official_anki.migration_cas_failed':
        return 'Legacy 迁移状态已被其他操作更新。';
      case 'official_anki.typed_field_unknown':
      case 'official_anki.typed_field_not_found':
        return '这张卡片没有可输入的字段。';
      case 'official_anki.typed_cloze_empty':
        return '这个填空没有可输入的内容。';
      case 'official_anki.typed_compare_failed':
        return '答案比对失败，可以重试或跳过。';
      default:
        return officialAnkiErrorFallback;
    }
  }
}
