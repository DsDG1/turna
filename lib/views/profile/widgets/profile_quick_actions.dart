// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

/// Tappable due chips: SRS review, mistakes, Anki review.
class ProfileQuickActions extends StatefulWidget {
  const ProfileQuickActions({super.key});

  @override
  State<ProfileQuickActions> createState() => _ProfileQuickActionsState();
}

class _ProfileQuickActionsState extends State<ProfileQuickActions> {
  @override
  void initState() {
    super.initState();
    unawaited(_refreshOfficialDue());
  }

  Future<void> _refreshOfficialDue() async {
    await const OfficialAnkiHomeDueSync().refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final mistakesCount =
        context.select((MistakeProvider p) => p.entries.length);
    final ankiDue = context.select(
      (SrsProvider p) => OfficialAnkiHomeDue.aggregatedAnkiDue(p.getDueWords()),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  color: TurnaTheme.brandTeal, size: 20),
              const SizedBox(width: 8),
              Text(
                AppStrings.profileQuickActionsTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuickChip(
                  icon: Icons.repeat_rounded,
                  label: AppStrings.profileQuickSrs,
                  count: srsDue,
                  accent: TurnaTheme.successDark,
                  onTap: () => context.router.push(const SrsReviewRoute()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickChip(
                  icon: Icons.error_outline_rounded,
                  label: AppStrings.profileQuickMistakes,
                  count: mistakesCount,
                  accent: TurnaTheme.error,
                  onTap: () => context.router.push(const MistakeReviewRoute()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickChip(
                  icon: Icons.layers_rounded,
                  label: AppStrings.profileQuickAnki,
                  count: ankiDue,
                  accent: TurnaTheme.leagueAmethyst,
                  onTap: () => context.router.push(const AnkiReviewRoute()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDue = count > 0;
    final bg =
        hasDue ? accent.withValues(alpha: 0.12) : TurnaTheme.cardBg(context);
    final border = hasDue
        ? accent.withValues(alpha: 0.35)
        : TurnaTheme.statCardBorder(context);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: hasDue ? accent : TurnaTheme.textHint, size: 22),
              const SizedBox(height: 6),
              Text(
                AppStrings.profileQuickDue(count),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color:
                          hasDue ? accent : TurnaTheme.textHintColor(context),
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
