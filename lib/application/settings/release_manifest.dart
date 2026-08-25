// Project imports:
import 'package:turna/views/settings/changelog_page.dart'
    show ChangelogRelease, JourneyStep;

/// Single structured source for the app's release history (Plan 2 §4.8/§7.2).
///
/// Two consumers must agree on release ids and ordering:
///   1. `assets/changelog.md` is the primary changelog shown in the app;
///   2. this manifest is used when the asset cannot be loaded.
///
/// `currentVersion` is deliberately not hardcoded here. The installed version
/// comes from [AppBuildInfo] and its matching release is highlighted at runtime.
class ReleaseManifest {
  const ReleaseManifest._();

  /// 版本历程（更新日志页顶部的历程卡）。
  static const List<JourneyStep> journeySteps = [
    JourneyStep(
      label: '0.x',
      title: '原型与上游',
      subtitle: '从早期多语言词汇原型开始',
    ),
    JourneyStep(
      label: '0.3',
      title: '离线学习框架',
      subtitle: '课程、复习与无障碍体验逐步完善',
    ),
    JourneyStep(
      label: '0.4',
      title: '土耳其语转向',
      subtitle: '中文界面、土耳其语课程与 AI 助手上线',
    ),
    JourneyStep(
      label: '0.5',
      title: '记忆与 AI 升级',
      subtitle: '个性化复习、Anki 兼容与 AI 体验提升',
    ),
    JourneyStep(
      label: '0.6',
      title: '伴学与内容扩充',
      subtitle: 'AI 问答、学习诊断与土耳其语八章内容',
    ),
    JourneyStep(
      label: '0.7',
      title: 'Anki 与课程整合',
      subtitle: '导入、课程管理、复习和远程备份统一体验',
    ),
    JourneyStep(
      label: '0.7.2',
      title: 'Anki 可靠性优化',
      subtitle: '多牌组复习、浏览统计与迁移恢复更稳定',
    ),
  ];

  /// `assets/changelog.md` 加载失败时使用的内置后援。
  static const List<ChangelogRelease> fallbackReleases = [
    ChangelogRelease(
      version: '0.7.2',
      title: 'Anki 导入与复习体验优化',
      items: [
        '每个 Anki 来源现在会作为独立课程显示，多次导入和多牌组管理更清晰',
        '“复习全部”可连续覆盖多个 Anki 来源，待复习数量、卡片顺序与实际复习保持一致',
        '课程管理页新增卡片浏览、牌组统计和旧数据迁移入口',
        '优化卡片样式、图片、音频和复杂内容的显示与播放',
        '导入、重新导入、删除和迁移支持更稳妥的中断恢复，减少重复或残留数据',
        '修复课程切换、牌组定位和删除范围不准确的问题',
        '提升备份恢复、存储清理和整体运行稳定性',
      ],
    ),
    ChangelogRelease(
      version: '0.7.1',
      title: '数据安全与体验打磨',
      items: [
        '更新常用 AI 服务预设，并加入可选的深度思考模式',
        'AI 密钥改用系统安全存储，导出数据时不会携带敏感信息',
        '优化 AI 回复、取消和重试体验，减少长回复时的界面卡顿',
        '新增“存储与性能”页面，可查看空间占用并清理可再生成的缓存',
        '修复成就奖励重复发放与连续学习天数统计不准确的问题',
        '备份恢复后，语言、无障碍和常用设置可以立即生效',
        '精简不再使用的功能与旧资源，并统一版本展示方式',
      ],
    ),
    ChangelogRelease(
      version: '0.7',
      title: 'Anki、课程与复习整合',
      items: [
        '改进 Anki 牌组导入与复习兼容性，复杂卡片显示更完整',
        '大型牌组导入更省内存，并可在中断后安全恢复',
        '课程与复习入口重新整合，牌组状态和课程切换更直观',
        '支持导入导出及 WebDAV 远程备份',
        '优化个人页、学习统计与成就展示',
        'AI 伴学加入更贴合学习进度的提示和讲解',
        '新增系统状态检查，便于发现存储、数据与兼容性问题',
        '更新 Turna 吉祥物、主页欢迎和学习场景插画',
      ],
    ),
    ChangelogRelease(
      version: '0.6',
      title: 'AI 伴学与土耳其语内容扩充',
      items: [
        'AI 伴学新增自由问答、学习诊断、讲解收藏、词典扩展和 Anki 卡片讲解',
        '课内提示会结合学习水平、错题和讲解偏好给出回复',
        'AI 中心重新分区，问答、诊断、收藏和创作入口更清晰',
        '土耳其语内置课程扩充为 A1 至 B2 八章、约 54 课',
        '统一讲解偏好和错误提示，并加强导出数据的隐私保护',
      ],
    ),
    ChangelogRelease(
      version: '0.5',
      title: '记忆复习与 AI 体验升级',
      items: [
        '更新个性化记忆复习方式，让复习安排更贴合学习表现',
        '改进 Anki 牌组识别和卡片显示，支持更多复杂牌组',
        'AI 请求支持取消，回复与网络错误处理更稳定',
        '重做课程管理、AI 中心、应用图标和多处界面文案',
        '新增记忆曲线、复习进度和学习建议面板',
      ],
    ),
    ChangelogRelease(
      version: '0.4',
      title: '土耳其语转向',
      items: [
        '界面文案全面中文化，设置与关于页体验统一',
        '新增 Anki 牌组导入和复习入口',
        '新增课内 AI 提示、课程设计和教材导入',
        '支持学习进度导出与导入',
        '完善主题、提醒、音效、无障碍和账户数据设置',
        '新增词典、弱词复习、每日挑战和学习统计',
        '学习目标语言由斯瓦希里语调整为土耳其语',
      ],
    ),
    ChangelogRelease(
      version: '0.3.x',
      title: '体验与可访问性',
      items: [
        '支持暗色、亮色和跟随系统主题',
        '新增字号、减弱动效、高对比度和阅读辅助选项',
        '加入感官减弱、专注模式与本地学习提醒',
        '课程树会标记已完成、薄弱和待复习内容',
        '课程内容更新时会提示，并提供进度重置选项',
        '移除不再使用的社交、付费和部分游戏化功能',
      ],
    ),
    ChangelogRelease(
      version: '0.3.0',
      title: '离线学习框架',
      items: [
        '完成离线优先的课程与学习框架',
        '支持多种课程结构和练习题型',
        '整合学习统计、词典、弱词复习和提醒',
        '补充自动化测试和发布检查',
      ],
    ),
    ChangelogRelease(
      version: 'ADR 0020',
      title: '土耳其语转向',
      items: [
        '学习目标语言由斯瓦希里语调整为土耳其语',
        '语音播放改用系统可用的语音服务',
        '建立 A1 至 B2 的八个学习分区',
        '完成第一章问候语内容，其余章节随后逐步补充',
      ],
    ),
    ChangelogRelease(
      version: '核心能力',
      title: '课程与复习',
      items: [
        '建立章节、单元和课程的学习层级',
        '支持入门、练习、听力、阅读、复习等多种课型',
        '加入间隔复习和错题重练',
        '学习数据保存在本地，无需云端账号',
      ],
    ),
    ChangelogRelease(
      version: '0.0.1',
      title: '原型',
      items: [
        '完成最初的西班牙语与卡纳达语词汇学习原型',
        '加入基础练习、动画、语音和配对玩法',
        '建立课程导航与学习数据保存能力',
      ],
    ),
  ];

  /// First release id in the fallback list. Release checks compare it with
  /// the first release in the bundled changelog.
  static String get latestFallbackReleaseId => fallbackReleases.first.version;

  /// Whether a release id matches the installed version (including a build
  /// suffix such as `0.7.2+3`).
  static bool releaseMatchesVersion({
    required String releaseId,
    required String installedVersion,
  }) {
    if (releaseId.isEmpty || installedVersion.isEmpty) return false;
    final normalized = installedVersion.split('+').first.trim();
    if (normalized.startsWith('$releaseId.') || normalized == releaseId) {
      return true;
    }
    return false;
  }
}
