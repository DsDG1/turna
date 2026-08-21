import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/domain/ai_companion/learner_profile_snapshot.dart';
import 'package:turna/domain/ai_companion/learning_evidence.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/repositories/i_learning_evidence_repository.dart';
import 'package:turna/service/locator.dart';

class LearnerProfileAssembler {
  LearnerProfileAssembler({
    required ILearningEvidenceRepository evidenceRepository,
    MistakeProvider? mistakeProvider,
    StudyStatsProvider? studyStatsProvider,
    SrsProvider? srsProvider,
    AppPrefs? appPrefs,
    AiExplainPrefsStore? aiPrefs,
  })  : _evidence = evidenceRepository,
        _mistakes = mistakeProvider,
        _stats = studyStatsProvider,
        _srs = srsProvider,
        _prefs = appPrefs,
        _aiPrefs = aiPrefs;

  final ILearningEvidenceRepository _evidence;
  final MistakeProvider? _mistakes;
  final StudyStatsProvider? _stats;
  final SrsProvider? _srs;
  final AppPrefs? _prefs;
  final AiExplainPrefsStore? _aiPrefs;

  Future<LearnerProfileSnapshot> build({
    String language = 'Turkish',
    String? cefrLevel,
    String? learningGoal,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    await _importLegacyMistakes();
    final evidence = await _evidence.recentEvidence(limit: 1000);
    final grouped = <String, List<LearningEvidence>>{};
    for (final item in evidence) {
      if (item.knowledgeType == KnowledgeType.unresolved) continue;
      grouped
          .putIfAbsent(
            '${item.knowledgeType.name}:${item.knowledgeId}',
            () => <LearningEvidence>[],
          )
          .add(item);
    }
    final mastery = <KnowledgeMastery>[];
    for (final items in grouped.values) {
      final first = items.first;
      final calculated = KnowledgeMastery.fromEvidence(
        first.knowledgeType,
        first.knowledgeId,
        items,
        now: at,
      );
      mastery.add(calculated);
      await _evidence.saveMastery(calculated);
    }

    final errors = <LearningErrorType, int>{};
    for (final item in evidence.where(
      (e) =>
          e.result == LearningResult.incorrect &&
          e.errorType != LearningErrorType.unknown,
    )) {
      errors.update(item.errorType, (count) => count + 1, ifAbsent: () => 1);
    }
    final frequentErrors = errors.keys.toList()
      ..sort((a, b) => (errors[b] ?? 0).compareTo(errors[a] ?? 0));

    var minutes7 = 0;
    var minutes30 = 0;
    if (_stats != null) {
      final days = await _stats.getLastNDays(30);
      minutes30 = days.fold(
        0,
        (sum, day) => sum + (day.totalDurationSeconds / 60).round(),
      );
      minutes7 = days.skip(days.length > 7 ? days.length - 7 : 0).fold(
            0,
            (sum, day) => sum + (day.totalDurationSeconds / 60).round(),
          );
    }
    final user = _prefs?.authUser.getValue();
    final companionPrefs = _aiPrefs?.snapshot;
    return LearnerProfileSnapshot(
      language: language,
      cefrLevel: cefrLevel,
      learningGoal: learningGoal,
      dailyMinutes: user?.dailyStudyMinutesGoal ?? 10,
      mastery: mastery,
      frequentErrorTypes: frequentErrors.take(4).toList(),
      dueReviewCount: (_srs?.dueCount ?? 0) + (_srs?.expressionDueCount ?? 0),
      studyMinutes7Days: minutes7,
      studyMinutes30Days: minutes30,
      builtAt: at,
      interests: const <String>[],
      preferredExplanationStyle: companionPrefs?.depth.name ?? 'standard',
      correctionIntensity: 'balanced',
      personalizationEnabled: companionPrefs?.injectLearnerContext ?? true,
    );
  }

  Future<void> _importLegacyMistakes() async {
    final provider = _mistakes;
    if (provider == null) return;
    for (final mistake in provider.entries) {
      final mapping = _knowledgeForMistake(mistake);
      await _evidence.appendEvidence(LearningEvidence(
        id: 'legacy_mistake_${mistake.id}',
        timestamp: mistake.timestamp,
        sourceType: LearningEvidenceSource.mistake,
        sourceId: mistake.id,
        knowledgeType: mapping.$1,
        knowledgeId: mapping.$2,
        questionType: mistake.interactionSnapshot?.runtimeType.toString(),
        result: LearningResult.incorrect,
        metadata: <String, dynamic>{
          'lessonId': mistake.lessonId,
          'stageId': mistake.stageId,
          'userAnswer': mistake.userAnswer,
          'correctAnswer': mistake.correctAnswer,
        },
      ));
    }
  }

  static (KnowledgeType, String) _knowledgeForMistake(MistakeEntry mistake) {
    if (mistake.wordId?.isNotEmpty ?? false) {
      return (KnowledgeType.word, mistake.wordId!);
    }
    if (mistake.expressionId?.isNotEmpty ?? false) {
      return (KnowledgeType.expression, mistake.expressionId!);
    }
    if (mistake.grammarPointId?.isNotEmpty ?? false) {
      return (KnowledgeType.grammar, mistake.grammarPointId!);
    }
    final fallback =
        mistake.interactionId.isNotEmpty ? mistake.interactionId : mistake.id;
    return (KnowledgeType.unresolved, fallback);
  }
}
