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
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/theme.dart';

class PlayHubScreen extends StatelessWidget {
  const PlayHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _QuickPlayCard(
              onTap: () => context.router.push(const MatchWordsRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _MistakesCard(
              onTap: () => context.router.push(const MistakeListRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _ReviewCard(
              onTap: () => context.router.push(const SrsReviewRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _GrammarReviewCard(
              onTap: () => context.router.push(const GrammarReviewRoute()),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DailyChallengeCard(
              onTap: () => context.router.push(const DailyChallengeRoute()),
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

class _QuickPlayCard extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickPlayCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VarnamalaTheme.peacockTeal,
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Play',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Match words as fast as you can',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MistakesCard extends StatelessWidget {
  final VoidCallback onTap;

  const _MistakesCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = context.select((MistakeProvider p) => p.count);

    return Material(
      color: VarnamalaTheme.error.withValues(alpha: 0.08),
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
                  color: VarnamalaTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: VarnamalaTheme.error,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Mistakes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: VarnamalaTheme.error,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count > 0
                          ? '$count mistakes to review (max 30)'
                          : 'No mistakes recorded',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: VarnamalaTheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: VarnamalaTheme.error.withValues(alpha: 0.6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final VoidCallback onTap;

  const _ReviewCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dueCount = context.select((SrsProvider p) => p.dueCount);

    return Material(
      color: VarnamalaTheme.success.withValues(alpha: 0.12),
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
                  color: VarnamalaTheme.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.repeat_rounded,
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
                      'Review',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: VarnamalaTheme.success,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dueCount > 0
                          ? '$dueCount words due for review'
                          : 'No words due right now',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              if (dueCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: VarnamalaTheme.success,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$dueCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: VarnamalaTheme.success.withValues(alpha: 0.6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GrammarReviewCard extends StatelessWidget {
  final VoidCallback onTap;

  const _GrammarReviewCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dueCount = context.select((GrammarReviewProvider p) => p.dueCount);

    return Material(
      color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
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
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: VarnamalaTheme.peacockTeal,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grammar Review',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: VarnamalaTheme.peacockTeal,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dueCount > 0
                          ? '$dueCount grammar points due for review'
                          : 'No grammar due right now',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              if (dueCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: VarnamalaTheme.peacockTeal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$dueCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyChallengeCard extends StatelessWidget {
  final VoidCallback onTap;

  const _DailyChallengeCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.12),
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
                  color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: VarnamalaTheme.leagueAmethyst,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Challenge',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: VarnamalaTheme.leagueAmethyst,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Random 15 questions — test your Swahili',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.6),
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
