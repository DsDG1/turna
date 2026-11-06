import 'dart:math';

import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/interaction_rules.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/stage.dart';

class ReviewLessonSampler {
  const ReviewLessonSampler();

  static const int maxMistakeBoost = 3;

  Lesson sample(
    Lesson lesson, {
    required List<MistakeEntry> mistakes,
    required Random random,
  }) {
    final policy = lesson.content.reviewPolicy;
    if (policy == null) return lesson;

    final pool = <Interaction>[
      for (final stage in lesson.content.stages) ...stage.items,
    ];
    if (pool.isEmpty) return lesson;

    final mistakeCounts = <String, int>{};
    for (final mistake in mistakes) {
      final snapshot = mistake.interactionSnapshot;
      if (snapshot == null || !isReviewPoolInteraction(snapshot)) continue;
      final type = interactionRuntimeType(snapshot);
      mistakeCounts[type] = (mistakeCounts[type] ?? 0) + 1;
    }

    final targetCount =
        policy.minItems + random.nextInt(policy.maxItems - policy.minItems + 1);
    final remaining = List<Interaction>.of(pool);
    final selected = <Interaction>[];

    while (selected.length < targetCount && remaining.isNotEmpty) {
      final weights = <double>[
        for (final item in remaining)
          _weightFor(item, policy.baseWeightFor, mistakeCounts),
      ];
      final total = weights.fold<double>(0, (sum, weight) => sum + weight);
      var ticket = random.nextDouble() * total;
      var selectedIndex = weights.length - 1;
      for (var i = 0; i < weights.length; i++) {
        ticket -= weights[i];
        if (ticket <= 0) {
          selectedIndex = i;
          break;
        }
      }
      selected.add(remaining.removeAt(selectedIndex));
    }

    selected.shuffle(random);
    return lesson.copyWith(
      content: lesson.content.copyWith(
        stages: [
          Stage(
            id: '${lesson.id}-review-session',
            name: lesson.name,
            items: selected,
          ),
        ],
      ),
    );
  }

  double _weightFor(
    Interaction item,
    double Function(String) baseWeightFor,
    Map<String, int> mistakeCounts,
  ) {
    final type = interactionRuntimeType(item);
    final boost = min(mistakeCounts[type] ?? 0, maxMistakeBoost);
    return baseWeightFor(type) * (1 + boost);
  }
}
