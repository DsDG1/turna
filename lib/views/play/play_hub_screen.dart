// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';

class PlayHubScreen extends StatelessWidget {
  const PlayHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);
    final mistakesCount = mistakes.length;
    final weakCount =
        WeakWordQuizAssembler.aggregateWeakWords(mistakes).length;
    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final grammarDue = context.select((GrammarReviewProvider p) => p.dueCount);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: 'Quick Play',
              subtitle: 'Match words as fast as you can',
              icon: Icons.bolt_rounded,
              accentColor: VarnamalaTheme.peacockTeal,
              filled: true,
              onTap: () => context.router.push(const MatchWordsRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: '错题复习',
              subtitle: mistakesCount > 0
                  ? '$mistakesCount 道错题，最多练习 10 题'
                  : '没有错题记录',
              icon: Icons.error_outline_rounded,
              accentColor: VarnamalaTheme.error,
              badge: mistakesCount > 0 ? '$mistakesCount' : null,
              onTap: () => context.router.push(const MistakeReviewRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: 'Review',
              subtitle: srsDue > 0
                  ? '$srsDue words due for review'
                  : 'No words due right now',
              icon: Icons.repeat_rounded,
              accentColor: VarnamalaTheme.success,
              badge: srsDue > 0 ? '$srsDue' : null,
              onTap: () => context.router.push(const SrsReviewRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: 'Grammar Review',
              subtitle: grammarDue > 0
                  ? '$grammarDue grammar points due for review'
                  : 'No grammar due right now',
              icon: Icons.menu_book_rounded,
              accentColor: VarnamalaTheme.peacockTeal,
              badge: grammarDue > 0 ? '$grammarDue' : null,
              onTap: () => context.router.push(const GrammarReviewRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: 'Daily Challenge',
              subtitle: 'Random 15 questions — test your Turkish',
              icon: Icons.calendar_today_rounded,
              accentColor: VarnamalaTheme.leagueAmethyst,
              onTap: () => context.router.push(const DailyChallengeRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: 'Weak Words',
              subtitle: weakCount > 0
                  ? '$weakCount words missed twice in 30 days'
                  : 'No weak words right now',
              icon: Icons.fitness_center_rounded,
              accentColor: VarnamalaTheme.warning,
              badge: weakCount > 0 ? '$weakCount' : null,
              onTap: () => context.router.push(const WeakWordsRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _PlayHubCard(
              title: 'Dictionary',
              subtitle: 'Search words, phrases, and grammar',
              icon: Icons.menu_book_outlined,
              accentColor: VarnamalaTheme.peacockCyan,
              onTap: () => context.router.push(const DictionaryRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _SectionTitle(title: 'Your Best'),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _StatsCard(),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

/// Shared play-hub action card. Use [filled] for the primary Quick Play style;
/// otherwise a tinted surface with accent icon/title (Phase 22 Weak Words can
/// reuse this widget).
class _PlayHubCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final String? badge;
  final bool filled;

  const _PlayHubCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.badge,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    const onAccent = VarnamalaTheme.textOnPrimary;
    final titleColor = filled ? onAccent : accentColor;
    final subtitleColor = filled
        ? onAccent.withValues(alpha: 0.9)
        : VarnamalaTheme.textSecondaryColor(context);
    final chevronColor = filled
        ? onAccent
        : accentColor.withValues(alpha: 0.6);
    final materialColor =
        filled ? accentColor : accentColor.withValues(alpha: 0.12);
    final iconBg = filled
        ? onAccent.withValues(alpha: 0.2)
        : accentColor.withValues(alpha: 0.2);
    final iconColor = filled ? onAccent : accentColor;

    return Material(
      color: materialColor,
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(16),
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
              if (badge != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: onAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: chevronColor,
                size: 18,
              ),
            ],
          ),
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

class _StatsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: context.read<GameProvider>().getUserGameStateStream(),
      builder: (context, snapshot) {
        final gameState = snapshot.data;
        final score = gameState?.score ?? 0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: VarnamalaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            border: Border.all(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: VarnamalaTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: VarnamalaTheme.success,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total XP',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      score.toString(),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: VarnamalaTheme.textPrimaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
