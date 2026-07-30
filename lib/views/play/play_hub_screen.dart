// Flutter imports:
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_review_assembler.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

class PlayHubScreen extends StatefulWidget {
  const PlayHubScreen({super.key});

  @override
  State<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends State<PlayHubScreen> {
  // 提升为字段，避免 5 个 context.select 触发 build 时重复分配 PageController。
  late final PageController _pageController =
      PageController(viewportFraction: 0.75);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);
    final mistakesCount = mistakes.length;
    final weakCount =
        WeakWordQuizAssembler.aggregateWeakWords(mistakes).length;
    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final grammarDue = context.select((GrammarReviewProvider p) => p.dueCount);
    final ankiDue = context.select(
      (SrsProvider p) => p
          .getDueWords()
          .where((w) => w.wordId.startsWith(AnkiReviewAssembler.ankiPrefix))
          .length,
    );

    final scrollView = CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: AppStrings.playQuickPlayTitle,
              subtitle: AppStrings.playQuickPlaySubtitle,
              icon: Icons.bolt_rounded,
              accentColor: VarnamalaTheme.peacockTeal,
              filled: true,
              onTap: () => context.router.push(const MatchWordsRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionTitle(title: AppStrings.playTodayFocusTitle),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 190,
            child: PageView(
              controller: _pageController,
              padEnds: false,
              children: [
                _FocusCardPage(
                  child: _FocusCard(
                    title: AppStrings.playMistakeReviewTitle,
                    countText: mistakesCount > 0
                        ? AppStrings.playMistakeFocusCount(mistakesCount)
                        : AppStrings.playMistakeFocusEmpty,
                    icon: Icons.error_outline_rounded,
                    accentColor: VarnamalaTheme.error,
                    badge: mistakesCount > 0 ? '$mistakesCount' : null,
                    onTap: () =>
                        context.router.push(const MistakeReviewRoute()),
                  ),
                ),
                _FocusCardPage(
                  child: _FocusCard(
                    title: AppStrings.playReviewTitle,
                    countText: srsDue > 0
                        ? AppStrings.playReviewFocusCount(srsDue)
                        : AppStrings.playReviewFocusEmpty,
                    icon: Icons.repeat_rounded,
                    accentColor: VarnamalaTheme.success,
                    badge: srsDue > 0 ? '$srsDue' : null,
                    onTap: () => context.router.push(const SrsReviewRoute()),
                  ),
                ),
                _FocusCardPage(
                  child: _FocusCard(
                    title: AppStrings.playDailyChallengeTitle,
                    countText: AppStrings.playDailyChallengeFocusCount,
                    icon: Icons.calendar_today_rounded,
                    accentColor: VarnamalaTheme.leagueAmethyst,
                    onTap: () =>
                        context.router.push(const DailyChallengeRoute()),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionTitle(title: AppStrings.playReviewCenterTitle),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _ReviewCell(
                  title: AppStrings.playWeakWordsTitle,
                  icon: Icons.fitness_center_rounded,
                  accentColor: VarnamalaTheme.warning,
                  badge: weakCount > 0 ? '$weakCount' : null,
                  onTap: () => context.router.push(const WeakWordsRoute()),
                ),
                _ReviewCell(
                  title: AppStrings.playGrammarReviewTitle,
                  icon: Icons.menu_book_rounded,
                  accentColor: VarnamalaTheme.peacockTeal,
                  badge: grammarDue > 0 ? '$grammarDue' : null,
                  onTap: () =>
                      context.router.push(const GrammarReviewRoute()),
                ),
                _ReviewCell(
                  title: AppStrings.playAnkiReviewTitle,
                  icon: Icons.style_rounded,
                  accentColor: VarnamalaTheme.peacockCyan,
                  badge: ankiDue > 0 ? '$ankiDue' : null,
                  onTap: () => context.router.push(const AnkiReviewRoute()),
                ),
                _ReviewCell(
                  title: AppStrings.playReviewTitle,
                  icon: Icons.repeat_rounded,
                  accentColor: VarnamalaTheme.success,
                  badge: srsDue > 0 ? '$srsDue' : null,
                  onTap: () => context.router.push(const SrsReviewRoute()),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SectionTitle(title: AppStrings.playToolsTitle),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: AppStrings.playReviewProgressTitle,
              subtitle: AppStrings.playReviewProgressSubtitle,
              icon: Icons.show_chart_rounded,
              accentColor: VarnamalaTheme.peacockTeal,
              onTap: () => context.router.push(const ReviewProgressRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: AppStrings.playDictionaryTitle,
              subtitle: AppStrings.playDictionarySubtitle,
              icon: Icons.menu_book_outlined,
              accentColor: VarnamalaTheme.peacockCyan,
              onTap: () => context.router.push(const DictionaryRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );

    // 半拟物玻璃：极光底层 + 单层 BackdropFilter 模糊 + RepaintBoundary 隔离。
    // 单层 BackdropFilter 比逐卡模糊便宜得多（约 0.5–1.5ms on low-end），
    // RepaintBoundary 让滚动只重绘 scroll 子树，不重绘极光与模糊层。
    return Stack(
      clipBehavior: Clip.antiAlias,
      children: [
        const Positioned.fill(child: _AuroraBackground()),
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: const SizedBox.shrink(),
          ),
        ),
        RepaintBoundary(child: scrollView),
      ],
    );
  }
}

/// 半拟物彩色极光底层：3 个径向光斑（左上 teal、右上 cyan、底部中央 amethyst）。
/// 静态，无 AnimationController，省电；外层用 RepaintBoundary 隔离滚动重绘。
class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 浅色 alpha 偏低保持「淡」；深色上调以抵消深底吸收。
    final tl = isDark ? 0.28 : 0.18;
    final tr = isDark ? 0.22 : 0.14;
    final bc = isDark ? 0.18 : 0.10;

    final scaffoldBg = VarnamalaTheme.scaffoldBg(context);

    return RepaintBoundary(
      child: SizedBox.expand(
        child: Stack(
          children: [
            // 兜底层：避免极光稀疏处露出 Material 默认白底。
            DecoratedBox(
              decoration: BoxDecoration(color: scaffoldBg),
              child: const SizedBox.expand(),
            ),
            // 左上 teal 光斑
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.6, -0.8),
                    radius: 0.9,
                    colors: [
                      VarnamalaTheme.peacockTeal.withValues(alpha: tl),
                      VarnamalaTheme.peacockTeal.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // 右上 cyan 光斑
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.1, -0.6),
                    radius: 0.85,
                    colors: [
                      VarnamalaTheme.peacockCyan.withValues(alpha: tr),
                      VarnamalaTheme.peacockCyan.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // 底部中央 amethyst 光斑（center 锁在 0.85，避免压到底栏）
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.0, 0.85),
                    radius: 1.0,
                    colors: [
                      VarnamalaTheme.leagueAmethyst.withValues(alpha: bc),
                      VarnamalaTheme.leagueAmethyst.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 玻璃卡片 4 层容器：
/// L0 基座（带描边 + 阴影），L1 ClipRRect 圆角，
/// L2 着色渐变， L3 顶部高光条，最后是 [child]。
///
/// [filled] 走深色玻璃底色（hero 用），单层 accent @ 0.18 阴影；
/// 否则走白色霜面 + 着色渐变，单层 accent @ 0.12 阴影。
/// 两类都比原先的 `glassShadow` 双层（blur 18 + 黑色微影）更克制，
/// 玻璃描边 + 顶部高光已表达立体感，避免 Grid 里阴影互相叠加。
class _GlassCard extends StatelessWidget {
  final Color accentColor;
  final bool filled;
  final VoidCallback? onTap;
  final Widget child;

  const _GlassCard({
    required this.accentColor,
    required this.child,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // filled 走「深色玻璃」底色（hero 用），非 filled 走白色霜面 + 着色渐变。
    final baseColor = filled
        ? accentColor.withValues(alpha: 0.85)
        : VarnamalaTheme.glassSurface(context);
    // 描边：filled 用更亮的白边以压住深底；非 filled 用主题感知的玻璃描边。
    final borderColor = filled
        ? Colors.white.withValues(alpha: 0.35)
        : VarnamalaTheme.glassBorder(context);
    // 阴影：filled 单层 accent @ 0.18（teal @0.85 底本身已经够「重」，
    // 不需要再叠双层）；非 filled 单层 accent @ 0.12。整体比 glassShadow
    // 双层（blur 18 + 黑色微影）更克制，配合玻璃描边 + 顶部高光已经能
    // 表达「悬浮」，避免 Grid 里 4 张格子阴影互相重叠成糊状。
    final shadowList = filled
        ? <BoxShadow>[
            BoxShadow(
              color: accentColor.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: accentColor.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ];
    // 高光条 alpha：filled 用更亮的白边高光；非 filled 用主题 helper。
    final highlight = filled
        ? Colors.white.withValues(alpha: 0.55)
        : VarnamalaTheme.glassHighlight(context);
    // 着色渐变：filled 给一个稍深的同色调去填充底色；非 filled 走 helper。
    final tintTop = filled
        ? Colors.white.withValues(alpha: 0.10)
        : VarnamalaTheme.glassAccentFill(accentColor);
    final tintBottom = filled
        ? accentColor.withValues(alpha: 0)
        : accentColor.withValues(alpha: 0.06);

    // 玻璃圆角：所有 hub 卡片统一 [VarnamalaTheme.radiusLarge]。
    const clip = BorderRadius.all(
      Radius.circular(VarnamalaTheme.radiusLarge),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: clip,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: shadowList,
      ),
      child: ClipRRect(
        borderRadius: clip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: clip,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [tintTop, tintBottom],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: double.infinity,
                    height: 1.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [highlight, Colors.transparent],
                      ),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared play-hub action card. Use [filled] for the primary Quick Play style;
/// otherwise a tinted surface with accent icon/title.
class _PlayHubCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool filled;

  const _PlayHubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    const onAccent = VarnamalaTheme.textOnPrimary;
    // filled 走「深色玻璃」文字保持白色（hero 卡在 teal @0.85 底上仍可读）。
    final titleColor = filled
        ? onAccent
        : VarnamalaTheme.textPrimaryColor(context);
    final subtitleColor = filled
        ? onAccent.withValues(alpha: 0.85)
        : VarnamalaTheme.textSecondaryColor(context);
    final chevronColor = filled
        ? onAccent
        : accentColor.withValues(alpha: 0.7);
    // 图标 chip：filled 用半透明白底；非 filled 用 accent 中等 alpha 底。
    final iconBg = filled
        ? onAccent.withValues(alpha: 0.22)
        : accentColor.withValues(alpha: 0.28);
    final iconColor = filled ? onAccent : accentColor;

    return _GlassCard(
      accentColor: accentColor,
      filled: filled,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(16),
                border: filled
                    ? Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 0.5,
                      )
                    : null,
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: filled ? 32 : 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: (filled
                            ? Theme.of(context).textTheme.titleLarge
                            : Theme.of(context).textTheme.titleMedium)
                        ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: subtitleColor,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: chevronColor,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// A swipeable "Today's Focus" card: tinted surface, icon + count badge on
/// top, title and a prominent count line, plus a start affordance.
class _FocusCard extends StatelessWidget {
  final String title;
  final String countText;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final String? badge;

  const _FocusCard({
    required this.title,
    required this.countText,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      accentColor: accentColor,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 26),
                ),
                const Spacer(),
                if (badge != null)
                  _CountBadge(label: badge!, color: accentColor),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              countText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: VarnamalaTheme.textPrimaryColor(context),
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  AppStrings.playStartAction,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: accentColor.withValues(alpha: 0.7),
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Page wrapper for the Today's Focus [PageView]: left-aligns the first card
/// with the rest of the page and peeks the next card on the right.
class _FocusCardPage extends StatelessWidget {
  final Widget child;

  const _FocusCardPage({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 8),
      child: child,
    );
  }
}

/// Compact Review Center cell: icon, title, optional count badge — no
/// subtitle text.
class _ReviewCell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final String? badge;

  const _ReviewCell({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      accentColor: accentColor,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const Spacer(),
                if (badge != null)
                  _CountBadge(
                    label: badge!,
                    color: accentColor,
                    circular: true,
                  ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: accentColor.withValues(alpha: 0.7),
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 小号玻璃 chip：accent 实色 + 白边高光 + 轻阴影。
/// 默认 pill 形态；[circular] 时切换为圆形（用于复习宫格小格子）。
class _CountBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool circular;

  const _CountBadge({
    required this.label,
    required this.color,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = circular
        ? const BorderRadius.all(Radius.circular(VarnamalaTheme.radiusRound))
        : const BorderRadius.all(Radius.circular(VarnamalaTheme.radiusMedium));

    return Container(
      padding: circular
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VarnamalaTheme.glassBadgeFill(color),
        borderRadius: radius,
        border: Border.all(
          color: VarnamalaTheme.glassHighlight(context),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: VarnamalaTheme.textOnPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: VarnamalaTheme.textPrimaryColor(context),
            ),
      ),
    );
  }
}