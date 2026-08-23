// Project imports:
import 'package:turna/views/settings/changelog_page.dart'
    show ChangelogRelease, JourneyStep;

/// Single structured source for the app's release history (Plan 2 §4.8/§7.2).
///
/// Two consumers must agree on release ids and ordering:
///   1. `assets/changelog.md` is the *primary* source the changelog page
///      renders from;
///   2. this manifest is the *fallback* when the asset fails to load, and the
///      reference CI/发布检查 compare against, so the fallback can no longer
///      silently diverge into a second hand-written version list.
///
/// `currentVersion` is deliberately NOT hardcoded here: the installed version
/// comes exclusively from [AppBuildInfo] (PackageInfo), and the changelog
/// entry matching it is highlighted at render time.
class ReleaseManifest {
  const ReleaseManifest._();

  /// 版本历程（原 changelog_page 顶部"更新历程"卡）。
  ///
  /// 自 0.7 起统一降级到 0.x 编号：原 1.3.0→0.7、1.2.0→0.6、1.1.0→0.5、
  /// 1.0.0→0.4、0.4.x→0.3.x、0.4.0→0.3.0。
  static const List<JourneyStep> journeySteps = [
    JourneyStep(
      label: '0.x',
      title: '原型与上游',
      subtitle: '2024 卡纳达 / 西班牙语原型 → 2026-03 fork',
    ),
    JourneyStep(
      label: '0.3.0',
      title: '离线优先重写',
      subtitle: 'Firebase 下线,SQLite + SRS + 13 种交互题型',
    ),
    JourneyStep(
      label: '0.3.x',
      title: 'future4 收尾',
      subtitle: '整洁架构 + 体验 / 可访问性',
    ),
    JourneyStep(
      label: '0.4',
      title: '土耳其语转向',
      subtitle: '语言由斯瓦希里语改为土耳其语,AI 助手上线',
    ),
    JourneyStep(
      label: '0.5',
      title: 'FSRS / AI / Anki',
      subtitle: '连续记忆模型、AI 引擎重构、Anki 智能化',
    ),
    JourneyStep(
      label: '0.6',
      title: 'AI 伴学与内容扩充',
      subtitle: '自由问答 / 诊断 / 收藏；土耳其语八章真实内容',
    ),
    JourneyStep(
      label: '0.7',
      title: 'Anki 官方 Core 整合',
      subtitle: '官方 rslib 整合、课程复习大一统、远程备份',
    ),
  ];

  /// 硬编码后援：`assets/changelog.md` 加载失败时使用。
  static const List<ChangelogRelease> fallbackReleases = [
    ChangelogRelease(
      version: '0.7',
      title: 'Anki 官方 Core 整合与课程/复习大一统',
      items: [
        '官方 Anki rslib 通过 Dart FFI 整合并默认切到官方 Core（ADR 0036/0037 落地）',
        '课程与复习大一统：统一复习 ledger、卡片引入资格（CardIntroductionStore）与二元 recall flow',
        '大型牌组导入走 worker isolate + 流式解压 + 500 条批次写入，内存占用不随牌组大小增长',
        '官方导入事务恢复：dry-run 演练、物理备份、逐源 allowlist 与独立 commit 边界（CI 拦截 BACKEND_COMMIT 漂移）',
        '新增 deleteNotes 操作硬删除笔记与关联数据',
        '课程页大改版：课程树扁平化、滚动隐藏栏、状态角标与 section switcher 翻新',
        '数据导入导出 + WebDAV 远程备份同步（manifest / snapshot / restore / 演练）',
        '个人页精简：今日概览卡 + 成就 showAll 独立路由 + 学习统计瘦身',
        '成就系统重构：evaluator / state repository / migration service / 详情 sheet / 徽章卡',
        '路由统一：RouteType.adaptive + Android 预测性返回 + 全 AutoRoute 推送（移除手写 MaterialPageRoute）',
        'AI 伴学打磨：移除成熟度象限、interaction renderer 调整、AI 深度导师 / ShowWord 翻面',
        '系统健康监控中心（SystemHealthMonitor）+ AI 伴侣 stack（profile / retriever / 预算 / 凭据）',
        '教学 Playground 新增：language_playground_eligibility / 装配器 / 内容源 / 入口页',
        '少量 bug 修复与 play_hub 黄金图更新',
      ],
    ),
    ChangelogRelease(
      version: '0.6',
      title: 'AI 伴学与土耳其语内容扩充',
      items: [
        'AI 伴学全面升级：自由问答、学习诊断、讲解收藏、词典 AI 扩展、Anki 卡片讲解',
        '课内提示支持流式回复，并注入学习者上下文（水平、错题、讲解偏好）',
        'AI Hub 重组为伴学优先：自由问答 / 诊断 / 收藏讲解与创作类入口分区更清晰',
        '统一讲解偏好（回复语言、深度、是否允许给答案）与友好错误提示',
        '土耳其语内置课程大幅扩充：约 148 词、18 表达、8 语法点、54 课（A1→B2 八章）',
        '进度导出不再包含 API Key；移除小艺（Xiaoyi）桥接，统一走本地 AI 引擎',
      ],
    ),
    ChangelogRelease(
      version: '0.5',
      title: '间隔重复与 AI 引擎升级',
      items: [
        'FSRS 连续记忆模型与本地参数优化，复习曲线更贴合个人记忆',
        'Anki 智能牌组归类与牌型渲染重构，支持复杂 .apkg / .colpkg',
        'AI 引擎刷新：内存与磁盘缓存、可取消令牌、统一 HTTP 客户端',
        '课程管理页、AI 中心、应用图标、文案与本地化整体重写',
        '记忆曲线、复习进度与 SRS 学习导师等新面板',
      ],
    ),
    ChangelogRelease(
      version: '0.4',
      title: '土耳其语转向',
      items: [
        '界面文案全面中文化，设置与关于页统一体验',
        'Anki 牌组导入（.apkg / .colpkg）与 Anki 复习入口',
        '课内 AI 提示助手，支持 DeepSeek 等兼容接口',
        'AI 课程设计器、教材导入与进度导出/导入',
        '独立设置页：主题、提醒、音效、无障碍与账户数据',
        '词典搜索、弱词复习、每日挑战与学习统计仪表盘',
        '暗色 / 亮色 / 跟随系统主题',
      ],
    ),
    ChangelogRelease(
      version: '0.3.x',
      title: '体验与可访问性',
      items: [
        '无障碍：字号、减弱动效、高对比度、阅读障碍友好字体',
        '感官减弱与专注模式等神经多样性友好选项',
        '本地每日学习提醒（无 streak 修复付费逻辑）',
        '课程树完成 / 薄弱 / 待复习状态角标',
        '课程内容版本变更提示与进度重置选项',
      ],
    ),
    ChangelogRelease(
      version: '0.3.0',
      title: 'future4 框架',
      items: [
        '整洁架构收尾：DI 整合、音频与内容解耦、路由守卫',
        'SRS 队列基类、GameProvider 拆分与外观模式',
        '集成测试、Golden 基线与一键发布流水线',
        '学习统计、词典、弱词与提醒等能力合入主线',
      ],
    ),
    ChangelogRelease(
      version: 'ADR 0020',
      title: '土耳其语转向',
      items: [
        '目标语言由斯瓦希里语迁移为土耳其语（TTS：tr）',
        '移除 Piper 离线模型，改用系统 / Google TTS',
        '第 1 章问候语真实内容（词汇 + 表达），2–8 章占位待填充',
        '8 个 CEFR 分区（A1→B2）与区间前置依赖',
      ],
    ),
    ChangelogRelease(
      version: '核心能力',
      title: '课程与复习引擎',
      items: [
        'Section → Unit → Lesson 层级与 13 种交互题型',
        '6 种课型模板：intro / practice / listening / reading / review / mastery',
        'SM-2 间隔重复（词汇 + 语法）与错题本 FIFO',
        'Match Madness 配对小游戏、纯本地 SQLite，无云端账号',
      ],
    ),
  ];

  /// First release id in the fallback list — the "latest" the fallback can
  /// speak about. 发布检查用它与 changelog.md 首项对齐。
  static String get latestFallbackReleaseId => fallbackReleases.first.version;

  /// Whether a changelog release id matches the installed version's major
  /// minor prefix (e.g. installed 0.7.0+1 ↔ release id '0.7').
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
