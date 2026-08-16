import 'dart:convert';

enum DiagnosisDataSufficiency { low, medium, high }

class DiagnosisWeakAreaEvidence {
  const DiagnosisWeakAreaEvidence({
    required this.knowledgeId,
    required this.title,
    required this.severity,
    required this.confidence,
    required this.evidenceIds,
    required this.recommendedAction,
    required this.estimatedMinutes,
  });

  final String knowledgeId;
  final String title;
  final String severity;
  final double confidence;
  final List<String> evidenceIds;
  final String recommendedAction;
  final int estimatedMinutes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'knowledgeId': knowledgeId,
        'title': title,
        'severity': severity,
        'confidence': confidence,
        'evidenceIds': evidenceIds,
        'recommendedAction': recommendedAction,
        'estimatedMinutes': estimatedMinutes,
      };
}

class DiagnosisSnapshot {
  const DiagnosisSnapshot({
    required this.id,
    required this.createdAt,
    required this.dataWindowDays,
    required this.dataSufficiency,
    required this.weakAreas,
    this.narrative = '',
    this.promptVersion = '',
  });

  final String id;
  final DateTime createdAt;
  final int dataWindowDays;
  final DiagnosisDataSufficiency dataSufficiency;
  final List<DiagnosisWeakAreaEvidence> weakAreas;
  final String narrative;
  final String promptVersion;

  String get weakAreasJson =>
      jsonEncode(weakAreas.map((e) => e.toJson()).toList());
}
