import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:turna/data/ai_companion_repository.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/ai_companion/ai_note.dart';
import 'package:turna/domain/ai_companion/ai_request_metric.dart';
import 'package:turna/domain/ai_companion/ai_session.dart';
import 'package:turna/domain/ai_companion/learning_evidence.dart';
import 'package:turna/domain/ai_companion/study_plan.dart';

void main() {
  late CourseDatabase db;
  late AiCompanionRepository repository;

  setUp(() {
    db = CourseDatabase(NativeDatabase.memory());
    repository = AiCompanionRepository(db);
  });

  tearDown(() => db.close());

  test('persists and restores a session with ordered messages', () async {
    final now = DateTime(2026, 8, 6, 12);
    const sessionId = 's1';
    await repository.saveSession(AiSession(
      id: sessionId,
      mode: AiSessionMode.qa,
      title: '宾格问答',
      language: 'Turkish',
      createdAt: now,
      updatedAt: now,
      promptVersion: 'companion.v1',
    ));
    await repository.saveMessage(AiSessionMessage(
      id: 'm1',
      sessionId: sessionId,
      role: 'user',
      content: '宾格是什么？',
      createdAt: now,
    ));
    await repository.saveMessage(AiSessionMessage(
      id: 'm2',
      sessionId: sessionId,
      role: 'assistant',
      content: '先观察词尾。',
      createdAt: now.add(const Duration(seconds: 1)),
    ));

    final restored = await repository.sessionById(sessionId);
    final messages = await repository.messagesForSession(sessionId);
    expect(restored?.title, '宾格问答');
    expect(messages.map((m) => m.id), ['m1', 'm2']);
    expect((await repository.latestActiveSession())?.id, sessionId);
  });

  test('evidence round-trips and produces bounded mastery', () async {
    final evidence = <LearningEvidence>[
      LearningEvidence(
        id: 'e1',
        timestamp: DateTime(2026, 8, 5),
        sourceType: LearningEvidenceSource.lesson,
        sourceId: 'lesson-1',
        knowledgeType: KnowledgeType.grammar,
        knowledgeId: 'accusative',
        result: LearningResult.incorrect,
      ),
      LearningEvidence(
        id: 'e2',
        timestamp: DateTime(2026, 8, 6),
        sourceType: LearningEvidenceSource.diagnosisCheck,
        sourceId: 'verify-1',
        knowledgeType: KnowledgeType.grammar,
        knowledgeId: 'accusative',
        result: LearningResult.correct,
        hintLevelUsed: 1,
      ),
    ];
    for (final item in evidence) {
      await repository.appendEvidence(item);
    }
    final stored = await repository.evidenceForKnowledge(
      KnowledgeType.grammar,
      'accusative',
    );
    final mastery = KnowledgeMastery.fromEvidence(
      KnowledgeType.grammar,
      'accusative',
      stored,
      now: DateTime(2026, 8, 6),
    );
    await repository.saveMastery(mastery);

    expect(stored, hasLength(2));
    expect(mastery.mastery, inInclusiveRange(0, 1));
    expect((await repository.allMastery()).single.knowledgeId, 'accusative');
  });

  test('plan and note remain actionable after reload', () async {
    final now = DateTime(2026, 8, 6);
    await repository.savePlan(StudyPlan(
      id: 'p1',
      title: '今日 10 分钟',
      createdAt: now,
      updatedAt: now,
      targetMinutes: 10,
      items: const <StudyPlanItem>[
        StudyPlanItem(
          id: 'pi1',
          planId: 'p1',
          kind: StudyPlanItemKind.srs,
          title: '复习到期词汇',
          estimatedMinutes: 4,
          order: 0,
          reason: '4 个词即将遗忘',
        ),
      ],
    ));
    await repository.saveNote(AiLearningNote(
      id: 'n1',
      title: '宾格词尾',
      body: '元音和谐决定词尾。',
      source: 'hint',
      createdAt: now,
      updatedAt: now,
      tags: const ['语法'],
    ));

    final plan = await repository.activePlan();
    expect(plan?.items.single.reason, '4 个词即将遗忘');
    await repository.updatePlanItemStatus(
      'pi1',
      StudyPlanItemStatus.completed,
    );
    expect((await repository.activePlan())?.items.single.status,
        StudyPlanItemStatus.completed);
    expect((await repository.searchNotes('元音')).single.id, 'n1');
  });

  test('request metrics aggregate without storing prompt text', () async {
    final now = DateTime(2026, 8, 6, 12);
    // A cache hit re-records the ORIGINAL request's tokens, but those were not
    // actually spent - usageSummary must exclude them so the daily budget
    // (AiBudgetManager) is not inflated by repeated cache hits.
    await repository.recordMetric(AiRequestMetric(
      requestId: 'r1',
      feature: 'lesson_hint',
      startedAt: now,
      latencyMs: 240,
      inputTokens: 80,
      outputTokens: 20,
      cacheHit: true,
      outcome: AiRequestOutcome.success,
    ));
    await repository.recordMetric(AiRequestMetric(
      requestId: 'r2',
      feature: 'lesson_hint',
      startedAt: now,
      latencyMs: 400,
      inputTokens: 60,
      outputTokens: 40,
      outcome: AiRequestOutcome.success,
    ));
    await repository.recordMetric(AiRequestMetric(
      requestId: 'r3',
      feature: 'lesson_hint',
      startedAt: now,
      latencyMs: 400,
      outcome: AiRequestOutcome.failed,
    ));

    final summary = await repository.usageSummary(
      since: DateTime(2026, 8, 6),
    );
    expect(summary.requests, 3);
    // Only r2 (the real network request) counts; r1's 100 cache-hit tokens are
    // excluded, and r3 failed with 0 tokens.
    expect(summary.totalTokens, 100);
    expect(summary.cacheHitRate, closeTo(1 / 3, 1e-9));
    expect(summary.failureRate, closeTo(1 / 3, 1e-9));
  });

  test('one-click companion clear leaves every store empty', () async {
    final now = DateTime(2026, 8, 6);
    await repository.saveSession(AiSession(
      id: 'clear-session',
      mode: AiSessionMode.qa,
      title: 'clear me',
      language: 'Turkish',
      createdAt: now,
      updatedAt: now,
    ));
    await repository.appendEvidence(LearningEvidence(
      id: 'clear-evidence',
      timestamp: now,
      sourceType: LearningEvidenceSource.aiChat,
      sourceId: 'clear-session',
      knowledgeType: KnowledgeType.unresolved,
      knowledgeId: 'clear-session',
      result: LearningResult.selfReported,
    ));
    await repository.recordMetric(AiRequestMetric(
      requestId: 'clear-request',
      feature: 'qa',
      startedAt: now,
      latencyMs: 1,
      outcome: AiRequestOutcome.success,
    ));

    await repository.clearAllCompanionData();

    expect(await repository.recentSessions(), isEmpty);
    expect(await repository.recentEvidence(), isEmpty);
    expect(await repository.allMastery(), isEmpty);
    expect(await repository.recentDiagnoses(), isEmpty);
    expect(await repository.activePlan(), isNull);
    expect(await repository.searchNotes(''), isEmpty);
    expect(
      (await repository.usageSummary(since: DateTime(2000))).requests,
      0,
    );
  });
}
