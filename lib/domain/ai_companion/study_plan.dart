enum StudyPlanStatus { active, completed, abandoned }

enum StudyPlanItemStatus { pending, active, completed, skipped }

enum StudyPlanItemKind { srs, lesson, weakArea, roleplay, verification }

class StudyPlanItem {
  const StudyPlanItem({
    required this.id,
    required this.planId,
    required this.kind,
    required this.title,
    required this.estimatedMinutes,
    required this.order,
    this.status = StudyPlanItemStatus.pending,
    this.reason = '',
    this.route,
    this.payloadJson = '{}',
  });

  final String id;
  final String planId;
  final StudyPlanItemKind kind;
  final String title;
  final int estimatedMinutes;
  final int order;
  final StudyPlanItemStatus status;
  final String reason;
  final String? route;
  final String payloadJson;
}

class StudyPlan {
  const StudyPlan({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.targetMinutes,
    this.status = StudyPlanStatus.active,
    this.items = const <StudyPlanItem>[],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int targetMinutes;
  final StudyPlanStatus status;
  final List<StudyPlanItem> items;

  int get completedItems =>
      items.where((e) => e.status == StudyPlanItemStatus.completed).length;
  int get estimatedMinutes =>
      items.fold(0, (sum, item) => sum + item.estimatedMinutes);

  static String newId() => 'plan_${DateTime.now().microsecondsSinceEpoch}';
}
