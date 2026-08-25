import 'dart:convert';
import 'dart:math' as math;

enum LearningEvidenceSource {
  lesson,
  mistake,
  srs,
  aiHint,
  aiChat,
  roleplay,
  diagnosisCheck,
}

enum KnowledgeType { word, expression, grammar, skill, unresolved }

enum LearningResult { correct, incorrect, partial, skipped, selfReported }

enum LearningErrorType {
  meaning,
  morphology,
  syntax,
  spelling,
  listening,
  fluency,
  unknown,
}

class LearningEvidence {
  const LearningEvidence({
    required this.id,
    required this.timestamp,
    required this.sourceType,
    required this.sourceId,
    required this.knowledgeType,
    required this.knowledgeId,
    required this.result,
    this.questionType,
    this.errorType = LearningErrorType.unknown,
    this.responseTimeMs,
    this.hintLevelUsed = 0,
    this.confidence = 1,
    this.metadata = const <String, dynamic>{},
    this.model,
    this.promptVersion,
    this.userConfirmed = true,
  });

  final String id;
  final DateTime timestamp;
  final LearningEvidenceSource sourceType;
  final String sourceId;
  final KnowledgeType knowledgeType;
  final String knowledgeId;
  final String? questionType;
  final LearningResult result;
  final LearningErrorType errorType;
  final int? responseTimeMs;
  final int hintLevelUsed;
  final double confidence;
  final Map<String, dynamic> metadata;
  final String? model;
  final String? promptVersion;
  final bool userConfirmed;

  String get metadataJson => jsonEncode(metadata);

  static String newId() => 'ev_${DateTime.now().microsecondsSinceEpoch}';
}

class KnowledgeMastery {
  const KnowledgeMastery({
    required this.knowledgeType,
    required this.knowledgeId,
    required this.mastery,
    required this.confidence,
    required this.evidenceCount,
    required this.updatedAt,
    this.lastSuccessfulRecallAt,
    this.stabilityDays = 0,
  });

  final KnowledgeType knowledgeType;
  final String knowledgeId;
  final double mastery;
  final double confidence;
  final int evidenceCount;
  final DateTime updatedAt;
  final DateTime? lastSuccessfulRecallAt;
  final double stabilityDays;

  /// Transparent first-pass mastery calculation used until enough evidence is
  /// available for a calibrated model. Recent, unhinted and transfer evidence
  /// carries more weight; elapsed time decays the score.
  static KnowledgeMastery fromEvidence(
    KnowledgeType type,
    String id,
    List<LearningEvidence> evidence, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final relevant = evidence
        .where((e) => e.knowledgeType == type && e.knowledgeId == id)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recent = relevant.take(12).toList();
    if (recent.isEmpty) {
      return KnowledgeMastery(
        knowledgeType: type,
        knowledgeId: id,
        mastery: 0,
        confidence: 0,
        evidenceCount: 0,
        updatedAt: at,
      );
    }

    var weightedCorrect = 0.0;
    var totalWeight = 0.0;
    DateTime? lastSuccess;
    final questionTypes = <String>{};
    for (var i = 0; i < recent.length; i++) {
      final e = recent[i];
      final recencyWeight = math.pow(0.88, i).toDouble();
      final hintWeight = math.max(0.35, 1 - (e.hintLevelUsed * 0.14));
      final confirmedWeight = e.userConfirmed ? 1.0 : 0.45;
      final weight =
          recencyWeight * hintWeight * confirmedWeight * e.confidence;
      final score = switch (e.result) {
        LearningResult.correct => 1.0,
        LearningResult.partial || LearningResult.selfReported => 0.5,
        LearningResult.incorrect || LearningResult.skipped => 0.0,
      };
      weightedCorrect += score * weight;
      totalWeight += weight;
      if (e.questionType?.isNotEmpty ?? false) {
        questionTypes.add(e.questionType!);
      }
      if (score == 1 &&
          (lastSuccess == null || e.timestamp.isAfter(lastSuccess))) {
        lastSuccess = e.timestamp;
      }
    }
    final base = totalWeight == 0 ? 0.0 : weightedCorrect / totalWeight;
    final days = lastSuccess == null
        ? 30.0
        : at.difference(lastSuccess).inHours.clamp(0, 24 * 365) / 24.0;
    final stability = math.max(1.0, recent.length * 1.5);
    final timeDecay = math.exp(-days / (stability * 3));
    final transferBonus =
        math.min(0.08, math.max(0, questionTypes.length - 1) * 0.02);
    final mastery = (base * timeDecay + transferBonus).clamp(0.0, 1.0);
    final confidence = (recent.length / 8.0).clamp(0.0, 1.0) *
        (0.8 + math.min(0.2, questionTypes.length * 0.05));

    return KnowledgeMastery(
      knowledgeType: type,
      knowledgeId: id,
      mastery: mastery,
      confidence: confidence.clamp(0.0, 1.0),
      evidenceCount: relevant.length,
      updatedAt: at,
      lastSuccessfulRecallAt: lastSuccess,
      stabilityDays: stability,
    );
  }
}
