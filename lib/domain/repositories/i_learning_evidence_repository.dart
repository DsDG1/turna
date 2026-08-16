import 'package:turna/domain/ai_companion/learning_evidence.dart';

abstract interface class ILearningEvidenceRepository {
  Future<void> appendEvidence(LearningEvidence evidence);
  Future<List<LearningEvidence>> recentEvidence({
    int limit = 200,
    DateTime? since,
  });
  Future<List<LearningEvidence>> evidenceForKnowledge(
    KnowledgeType type,
    String knowledgeId, {
    int limit = 100,
  });
  Future<void> saveMastery(KnowledgeMastery mastery);
  Future<List<KnowledgeMastery>> allMastery();
  Future<void> clearLearningInferences();
}
