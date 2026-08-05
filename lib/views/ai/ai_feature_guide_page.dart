// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/ai_depth_tutor_sheet.dart';
import 'package:turna/views/lesson/tutor_launch_sheet.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/theme.dart';

/// AI 助手功能介绍页 — 常驻手册。
///
/// 从 AI Hub AppBar 右上角 ❓ 进入。一页讲清楚 6 个主推功能（伴学 4 + 复习 2）
/// 是干嘛的、什么时候用、怎么操作、有啥小贴士。每张功能卡可直接点开对应功能。
///
/// 1.x 阶段中文硬编码；上 i18n 时把 [_FeatureSpec] 里的 5 个 String 字段
/// 改为 AppStrings 函数即可，结构不动。
@RoutePage()
class AiFeatureGuidePage extends StatelessWidget {
  const AiFeatureGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        centerTitle: true,
        title: const Text('AI 助手 · 功能介绍'),
      ),
      body: const _FeatureGuideContent(),
    );
  }
}

class _FeatureGuideContent extends StatelessWidget {
  const _FeatureGuideContent();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const SliverToBoxAdapter(child: _HeroCard()),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: '📘 伴学'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 3 ? 12 : 0),
                  child: _FeatureCard(spec: _kFeatures[i]),
                ),
                childCount: 4,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: '🎯 复习'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 1 ? 12 : 0),
                  child: _FeatureCard(spec: _kFeatures[4 + i]),
                ),
                childCount: 2,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Selector<AiEngineConfigHolder, _HeroSnapshot>(
      selector: (_, h) => _HeroSnapshot(
        preset: h.config.preset.label,
        complete: h.config.isComplete,
      ),
      builder: (context, snap, _) {
        const radius =
            BorderRadius.all(Radius.circular(TurnaTheme.radiusXLarge));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TurnaTheme.amethystLeague,
                  TurnaTheme.brandTeal,
                ],
              ),
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: TurnaTheme.amethystLeague.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '6 个 AI 能力，一次看懂',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '所有功能都依赖 AI 引擎。配置一次，全部可用。',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(
                      icon: snap.complete
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      label: snap.complete
                          ? '引擎已配置 · ${snap.preset}'
                          : '引擎未配置（点 AI Hub 顶部卡设置）',
                      warning: !snap.complete,
                    ),
                    const _HeroChip(
                      icon: Icons.lock_outline_rounded,
                      label: '隐私：仅本机 · 不联网',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroSnapshot {
  const _HeroSnapshot({required this.preset, required this.complete});
  final String preset;
  final bool complete;

  @override
  bool operator ==(Object other) =>
      other is _HeroSnapshot &&
      other.preset == preset &&
      other.complete == complete;

  @override
  int get hashCode => Object.hash(preset, complete);
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    this.warning = false,
  });
  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warning
            ? TurnaTheme.warning
            : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: Colors.white.withValues(alpha: warning ? 0.0 : 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Feature data ─────────────────────────────────────────────────────────

class _FeatureSpec {
  const _FeatureSpec({
    required this.icon,
    required this.accent,
    required this.title,
    required this.purpose,
    required this.scenarios,
    required this.steps,
    required this.tip,
    required this.open,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String purpose;
  final List<String> scenarios;
  final List<String> steps;
  final String tip;
  final void Function(BuildContext) open;
}

const List<_FeatureSpec> _kFeatures = [
  // 1. 自由问答
  _FeatureSpec(
    icon: Icons.chat_bubble_outline_rounded,
    accent: TurnaTheme.brandTeal,
    title: '自由问答',
    purpose: '跟 AI 老师自由对话，问任何土耳其语相关问题。',
    scenarios: [
      '学完一个语法点想再追问',
      '想知道某个词的真实用法和例句',
      '想让 AI 解释一段土耳其语句子',
    ],
    steps: [
      '点击卡片进入聊天页',
      '在输入框写下问题，回车发送',
      'AI 实时流式回答',
      '满意的回答可点 ❤ 收藏',
    ],
    tip: '问题越具体，AI 越懂你。比如「-dık 与 -acak 的区别」比「教我语法」有用。',
    open: _openTutorChat,
  ),
  // 2. 学习诊断
  _FeatureSpec(
    icon: Icons.analytics_outlined,
    accent: TurnaTheme.brandSky,
    title: '学习诊断',
    purpose: '让 AI 看你的学习数据，告诉你现在卡在哪、下一步该练什么。',
    scenarios: [
      '学了一阵想看看自己真实水平',
      '想找出反复错的题型',
      '想拿到一份定制化的下一步计划',
    ],
    steps: [
      '点击卡片进入诊断页',
      'AI 自动分析你最近的错题和弱词',
      '阅读诊断报告（强项 / 弱项 / 建议）',
      '可一键跳到「按错题练习」或「按弱词练习」',
    ],
    tip: '诊断基于你最近 7 天的真实数据；越常用 Turna，诊断越准。',
    open: _openDiagnosis,
  ),
  // 3. 收藏的回答
  _FeatureSpec(
    icon: Icons.bookmark_outline_rounded,
    accent: TurnaTheme.amethystLeague,
    title: '收藏的回答',
    purpose: '把 AI 给出但还想再看的回答集中放这里，随时回查。',
    scenarios: [
      '看到一个好回答想之后回看',
      '想整理一个「我的错题解释集」',
      '想对比同一问题几次回答的差异',
    ],
    steps: [
      '在自由问答 / 讲解页面点回答旁的 ❤',
      '自动进入「收藏的回答」',
      '点击单条可查看完整对话',
      '可长按删除或加笔记（待支持）',
    ],
    tip: '收藏多了就用「分类标签」找——目前按时间倒序排，1.x 后会加标签和搜索。',
    open: _openSaved,
  ),
  // 4. 深度讲解
  _FeatureSpec(
    icon: Icons.account_tree_outlined,
    accent: TurnaTheme.brandReed,
    title: '深度讲解',
    purpose: '对当前题目（错题、单词、语法）展开一次完整讲解，AI 现场分析。',
    scenarios: [
      '一道题错了想搞清楚为什么',
      '单词查了词典但还是记不住',
      '语法点想看更多例句和场景',
    ],
    steps: [
      '在题目 / 单词 / 语法点旁点「深度讲解」',
      '弹出讲解面板，AI 读上下文后开始写',
      '可继续追问或让 AI 再讲一遍',
      '满意的讲解可点 ❤ 收藏',
    ],
    tip: '讲解会注入你的水平、错题和讲解偏好——同义词用你认识的、深度跟你匹配。',
    open: _openDepthTutor,
  ),
  // 5. 按错题练习
  _FeatureSpec(
    icon: Icons.history_toggle_off_rounded,
    accent: TurnaTheme.brandTeal,
    title: '按错题练习',
    purpose: '让 AI 把你最近常错的题整理成一次专项练习。',
    scenarios: [
      '刚做完一组题，发现错得不少',
      '想集中攻克同一类错误',
      '想用错题替代普通复习',
    ],
    steps: [
      '点击卡片',
      '选时间范围（最近 7 / 30 天）',
      'AI 生成专项练习题',
      '做完进入评分，错题自动进 SRS',
    ],
    tip: '错题不够时会自动用同类高频错题补足，不用担心「最近没错就没得练」。',
    open: _openTutorMistakes,
  ),
  // 6. 按弱词练习
  _FeatureSpec(
    icon: Icons.quiz_rounded,
    accent: TurnaTheme.brandReed,
    title: '按弱词练习',
    purpose: '让 AI 把你记得最差的单词挑出来组一次练习。',
    scenarios: [
      '背单词时反复记不住某一批',
      '想针对性补足词汇量',
      'FSRS 算法推算你「忘了」的词',
    ],
    steps: [
      '点击卡片',
      '选词数量（10 / 20 / 50）',
      'AI 用这些弱词生成练习',
      '完成后 FSRS 自动更新记忆强度',
    ],
    tip: '「弱」是 FSRS 算出来的——能回忆但不稳的词比完全没学过的词更值得练。',
    open: _openTutorWeak,
  ),
];

// ─── Open helpers ─────────────────────────────────────────────────────────

void _openTutorChat(BuildContext context) =>
    context.router.push(const AiTutorChatRoute());

void _openDiagnosis(BuildContext context) =>
    context.router.push(const AiDiagnosisRoute());

void _openSaved(BuildContext context) =>
    context.router.push(const AiSavedListRoute());

void _openDepthTutor(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const AiDepthTutorSheet(),
  );
}

void _openTutorMistakes(BuildContext context) {
  // TutorLaunchSheet 内部自带 mistakes/weakWords 切换；此处打开后用户
  // 默认进 mistakes。需要从 mistakes 直进时再补 initial 参数。
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const TutorLaunchSheet(),
  );
}

void _openTutorWeak(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(TurnaTheme.radiusXLarge),
      ),
    ),
    builder: (_) => const TutorLaunchSheet(),
  );
}

// ─── Feature card ─────────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.spec});
  final _FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      accentColor: spec.accent,
      onTap: () => spec.open(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                AccentIconChip(
                  icon: spec.icon,
                  color: spec.accent,
                  size: 22,
                  padding: 9,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    spec.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: spec.accent,
                        ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: TurnaTheme.brandTeal,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 作用
            _SectionLabel(label: '作用', color: spec.accent),
            const SizedBox(height: 4),
            Text(
              spec.purpose,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textPrimaryColor(context),
                    height: 1.55,
                  ),
            ),
            const SizedBox(height: 12),
            // 适用场景
            _SectionLabel(label: '适用场景', color: spec.accent),
            const SizedBox(height: 4),
            for (final s in spec.scenarios)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 6),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: spec.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: TurnaTheme.textSecondaryColor(context),
                                  height: 1.5,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 操作流程
            _SectionLabel(label: '操作流程', color: spec.accent),
            const SizedBox(height: 4),
            for (var i = 0; i < spec.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: spec.accent,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        spec.steps[i],
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: TurnaTheme.textSecondaryColor(context),
                                  height: 1.5,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            // 小贴士
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: spec.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 16,
                    color: spec.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      spec.tip,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textPrimaryColor(context),
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
    );
  }
}
