import 'package:turna/domain/ai_companion/study_plan.dart';

abstract interface class IStudyPlanRepository {
  Future<void> savePlan(StudyPlan plan);
  Future<StudyPlan?> activePlan();
  Future<StudyPlan?> planById(String id);
  Future<void> updatePlanItemStatus(
    String itemId,
    StudyPlanItemStatus status,
  );
  Future<void> clearPlans();
}
