// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/course/reading_passage.dart';
import 'package:turna/views/theme.dart';

class LessonStageBanner extends StatelessWidget {
  final String name;
  final Color accent;

  const LessonStageBanner({
    super.key,
    required this.name,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: accent.withValues(alpha: 0.04),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class LessonReadingPassageCard extends StatelessWidget {
  final ReadingPassage passage;

  const LessonReadingPassageCard({super.key, required this.passage});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.leagueAmethyst.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.leagueAmethyst.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            passage.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
          ),
          const SizedBox(height: 12),
          ...passage.paragraphs.expand((paragraph) => [
                Text(
                  paragraph,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 12),
              ]),
        ],
      ),
    );
  }
}

class LessonLegacyReadingPassage extends StatelessWidget {
  final String text;

  const LessonLegacyReadingPassage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.leagueAmethyst.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(
          color: TurnaTheme.leagueAmethyst.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          height: 1.6,
          color: TurnaTheme.textPrimaryColor(context),
        ),
      ),
    );
  }
}
