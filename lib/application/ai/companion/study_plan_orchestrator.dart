import 'dart:math' as math;

import 'package:turna/domain/ai_companion/diagnosis_snapshot.dart';
import 'package:turna/domain/ai_companion/study_plan.dart';

class StudyPlanOrchestrator {
  const StudyPlanOrchestrator();

  StudyPlan build({
    required int availableMinutes,
    required int dueReviewCount,
    required List<DiagnosisWeakAreaEvidence> weakAreas,
    bool includeRoleplay = false,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final target = availableMinutes.clamp(5, 30);
    final id = StudyPlan.newId();
    final items = <StudyPlanItem>[];
    var used = 0;

    void add(
      StudyPlanItemKind kind,
      String title,
      int minutes,
      String reason,
      String route,
    ) {
      if (used >= target || minutes <= 0) return;
      final ceiling = kind == StudyPlanItemKind.verification
          ? target
          : math.max(3, target - 2);
      final actual = math.min(minutes, ceiling - used);
      if (actual < 2) return;
      items.add(StudyPlanItem(
        id: '${id}_${items.length}',
        planId: id,
        kind: kind,
        title: title,
        estimatedMinutes: actual,
        order: items.length,
        reason: reason,
        route: route,
      ));
      used += actual;
    }

    if (dueReviewCount > 0) {
      add(
        StudyPlanItemKind.srs,
        '复习到期内容',
        math.min(6, math.max(3, (dueReviewCount / 3).ceil())),
        '$dueReviewCount 项内容即将遗忘',
        'SrsReviewRoute',
      );
    }
    for (final area in weakAreas.take(2)) {
      add(
        StudyPlanItemKind.weakArea,
        '${area.title}专项练习',
        area.estimatedMinutes,
        '近期待加强 · 置信度 ${(area.confidence * 100).round()}%',
        'TutorLaunchRoute',
      );
    }
    if (includeRoleplay) {
      add(
        StudyPlanItemKind.roleplay,
        '情景对话',
        5,
        '在真实语境中迁移今天的知识',
        'AiTutorChatRoute',
      );
    }
    add(
      StudyPlanItemKind.verification,
      '退出小测',
      2,
      '验证今天的讲解是否真正掌握',
      'DailyChallengeRoute',
    );
    if (items.isEmpty) {
      add(
        StudyPlanItemKind.lesson,
        '继续当前课程',
        target,
        '保持课程进度与连续学习',
        'CourseRoute',
      );
    }

    return StudyPlan(
      id: id,
      title: '今日 $target 分钟计划',
      createdAt: at,
      updatedAt: at,
      targetMinutes: target,
      items: items,
    );
  }
}
