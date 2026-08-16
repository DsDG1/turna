import 'dart:math' as math;

import 'package:turna/domain/ai_companion/diagnosis_snapshot.dart';
import 'package:turna/domain/ai_companion/learning_evidence.dart';

class DeterministicDiagnosisEngine {
  const DeterministicDiagnosisEngine();

  DiagnosisSnapshot analyze({
    required List<LearningEvidence> evidence,
    required List<KnowledgeMastery> mastery,
    int dataWindowDays = 14,
    DateTime? now,
    int maxWeakAreas = 5,
  }) {
    final at = now ?? DateTime.now();
    final since = at.subtract(Duration(days: dataWindowDays));
    final window = evidence
        .where((e) => !e.timestamp.isBefore(since) && e.userConfirmed)
        .toList();
    final masteryById = <String, KnowledgeMastery>{
      for (final item in mastery)
        '${item.knowledgeType.name}:${item.knowledgeId}': item,
    };
    final grouped = <String, List<LearningEvidence>>{};
    for (final item in window) {
      if (item.knowledgeType == KnowledgeType.unresolved) continue;
      grouped
          .putIfAbsent(
            '${item.knowledgeType.name}:${item.knowledgeId}',
            () => <LearningEvidence>[],
          )
          .add(item);
    }

    final areas = <DiagnosisWeakAreaEvidence>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      final incorrect = items
          .where((e) =>
              e.result == LearningResult.incorrect ||
              e.result == LearningResult.partial)
          .length;
      if (incorrect == 0) continue;
      final localMastery = masteryById[entry.key];
      final ratio = incorrect / items.length;
      final masteryGap = 1 - (localMastery?.mastery ?? (1 - ratio));
      final confidence = math.min(
        1.0,
        (items.length / 6.0) * 0.7 + (localMastery?.confidence ?? 0) * 0.3,
      );
      final risk = (ratio * 0.6 + masteryGap * 0.4) * confidence;
      final severity = risk >= 0.6
          ? 'high'
          : risk >= 0.32
              ? 'medium'
              : 'low';
      final knowledgeId = items.first.knowledgeId;
      final knowledgeType = items.first.knowledgeType;
      final displayTitle = _displayTitle(
        knowledgeType: knowledgeType,
        knowledgeId: knowledgeId,
      );
      areas.add(DiagnosisWeakAreaEvidence(
        knowledgeId: knowledgeId,
        title: displayTitle,
        severity: severity,
        confidence: confidence,
        evidenceIds: items.map((e) => e.id).toList(),
        recommendedAction: 'micro_practice',
        estimatedMinutes: math.min(10, math.max(3, incorrect * 2)),
      ));
    }
    const rank = <String, int>{'high': 3, 'medium': 2, 'low': 1};
    areas.sort((a, b) {
      final bySeverity =
          (rank[b.severity] ?? 0).compareTo(rank[a.severity] ?? 0);
      return bySeverity != 0
          ? bySeverity
          : b.confidence.compareTo(a.confidence);
    });

    final sufficiency = window.length >= 12
        ? DiagnosisDataSufficiency.high
        : window.length >= 4
            ? DiagnosisDataSufficiency.medium
            : DiagnosisDataSufficiency.low;
    return DiagnosisSnapshot(
      id: 'diag_${at.microsecondsSinceEpoch}',
      createdAt: at,
      dataWindowDays: dataWindowDays,
      dataSufficiency: sufficiency,
      weakAreas: areas.take(maxWeakAreas).toList(),
    );
  }

  static String _displayTitle({
    required KnowledgeType knowledgeType,
    required String knowledgeId,
  }) {
    if (knowledgeId.trim().isEmpty) return knowledgeType.name;
    final looksLikeId = RegExp(r'^[a-z]+[-_:]\S+$').hasMatch(knowledgeId) ||
        knowledgeId.contains('_');
    if (!looksLikeId) return knowledgeId;
    return '${knowledgeType.name}: $knowledgeId';
  }
}
