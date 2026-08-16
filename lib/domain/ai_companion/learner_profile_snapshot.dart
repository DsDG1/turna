import 'learning_evidence.dart';

class LearnerProfileSnapshot {
  const LearnerProfileSnapshot({
    required this.language,
    required this.builtAt,
    this.cefrLevel,
    this.learningGoal,
    this.dailyMinutes = 10,
    this.mastery = const <KnowledgeMastery>[],
    this.frequentErrorTypes = const <LearningErrorType>[],
    this.dueReviewCount = 0,
    this.studyMinutes7Days = 0,
    this.studyMinutes30Days = 0,
    this.interests = const <String>[],
    this.preferredExplanationStyle = 'standard',
    this.correctionIntensity = 'balanced',
    this.personalizationEnabled = true,
  });

  final String language;
  final String? cefrLevel;
  final String? learningGoal;
  final int dailyMinutes;
  final List<KnowledgeMastery> mastery;
  final List<LearningErrorType> frequentErrorTypes;
  final int dueReviewCount;
  final int studyMinutes7Days;
  final int studyMinutes30Days;
  final List<String> interests;
  final String preferredExplanationStyle;
  final String correctionIntensity;
  final bool personalizationEnabled;
  final DateTime builtAt;

  String toPromptBlock({int maxItems = 8, int maxChars = 1400}) {
    final weakest = mastery.toList()
      ..sort((a, b) => a.mastery.compareTo(b.mastery));
    final out = StringBuffer()
      ..writeln('[LearnerProfile]')
      ..writeln('Language: $language');
    if (cefrLevel?.isNotEmpty ?? false) out.writeln('CEFR: $cefrLevel');
    if (learningGoal?.isNotEmpty ?? false) out.writeln('Goal: $learningGoal');
    out
      ..writeln('Daily minutes: $dailyMinutes')
      ..writeln('Due reviews: $dueReviewCount')
      ..writeln('Explanation style: $preferredExplanationStyle')
      ..writeln('Correction intensity: $correctionIntensity');
    if (interests.isNotEmpty) {
      out.writeln('Interests (examples only): ${interests.join(', ')}');
    }
    if (weakest.isNotEmpty) {
      out.writeln('Lowest mastery (local evidence):');
      for (final k in weakest.take(maxItems)) {
        out.writeln(
          '- ${k.knowledgeType.name}:${k.knowledgeId} '
          'mastery=${k.mastery.toStringAsFixed(2)} '
          'confidence=${k.confidence.toStringAsFixed(2)} '
          'evidence=${k.evidenceCount}',
        );
      }
    }
    if (frequentErrorTypes.isNotEmpty) {
      out.writeln(
        'Frequent error types: ${frequentErrorTypes.map((e) => e.name).join(', ')}',
      );
    }
    out.write('[/LearnerProfile]');
    final raw = out.toString();
    if (raw.length <= maxChars) return raw;
    return '${raw.substring(0, maxChars - 1)}…';
  }
}
