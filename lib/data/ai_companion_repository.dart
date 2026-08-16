import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:turna/data/course_database.dart';
import 'package:turna/domain/ai_companion/ai_note.dart';
import 'package:turna/domain/ai_companion/ai_request_metric.dart';
import 'package:turna/domain/ai_companion/ai_session.dart';
import 'package:turna/domain/ai_companion/diagnosis_snapshot.dart';
import 'package:turna/domain/ai_companion/learning_evidence.dart';
import 'package:turna/domain/ai_companion/study_plan.dart';
import 'package:turna/domain/repositories/i_ai_note_repository.dart';
import 'package:turna/domain/repositories/i_ai_metrics_repository.dart';
import 'package:turna/domain/repositories/i_ai_session_repository.dart';
import 'package:turna/domain/repositories/i_diagnosis_repository.dart';
import 'package:turna/domain/repositories/i_learning_evidence_repository.dart';
import 'package:turna/domain/repositories/i_study_plan_repository.dart';

/// Drift-backed durable store for the AI companion learning loop.
///
/// The tables are additive raw-SQL tables created by CourseDatabase schema
/// v16. Keeping the repository behind domain interfaces makes the same feature
/// usable through HarmonyOS RDB and easy to replace with a web implementation.
class AiCompanionRepository
    implements
        IAiSessionRepository,
        ILearningEvidenceRepository,
        IDiagnosisRepository,
        IStudyPlanRepository,
        IAiNoteRepository,
        IAiMetricsRepository {
  AiCompanionRepository(this._db);

  final CourseDatabase _db;

  @override
  Future<void> saveSession(AiSession session) async {
    await _db.customInsert(
      '''
      INSERT INTO ai_sessions (
        id, mode, title, language, goal_id, source_context_json,
        created_at, updated_at, summary, status, prompt_version, model,
        total_tokens, estimated_cost
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        mode = excluded.mode,
        title = excluded.title,
        language = excluded.language,
        goal_id = excluded.goal_id,
        source_context_json = excluded.source_context_json,
        updated_at = excluded.updated_at,
        summary = excluded.summary,
        status = excluded.status,
        prompt_version = excluded.prompt_version,
        model = excluded.model,
        total_tokens = excluded.total_tokens,
        estimated_cost = excluded.estimated_cost
      ''',
      variables: <Variable<Object>>[
        Variable<String>(session.id),
        Variable<String>(session.mode.name),
        Variable<String>(session.title),
        Variable<String>(session.language),
        Variable<String>(session.goalId),
        Variable<String>(jsonEncode(session.sourceContext)),
        Variable<int>(session.createdAt.millisecondsSinceEpoch),
        Variable<int>(session.updatedAt.millisecondsSinceEpoch),
        Variable<String>(session.summary),
        Variable<String>(session.status.name),
        Variable<String>(session.promptVersion),
        Variable<String>(session.model),
        Variable<int>(session.totalTokens),
        Variable<double>(session.estimatedCost),
      ],
    );
  }

  @override
  Future<AiSession?> sessionById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM ai_sessions WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    return rows.isEmpty ? null : _sessionFromRow(rows.first.data);
  }

  @override
  Future<AiSession?> latestActiveSession({AiSessionMode? mode}) async {
    final sql = mode == null
        ? "SELECT * FROM ai_sessions WHERE status = 'active' ORDER BY updated_at DESC LIMIT 1"
        : "SELECT * FROM ai_sessions WHERE status = 'active' AND mode = ? ORDER BY updated_at DESC LIMIT 1";
    final rows = await _db
        .customSelect(
          sql,
          variables: mode == null
              ? const <Variable<Object>>[]
              : <Variable<Object>>[Variable<String>(mode.name)],
        )
        .get();
    return rows.isEmpty ? null : _sessionFromRow(rows.first.data);
  }

  @override
  Future<List<AiSession>> recentSessions({int limit = 20}) async {
    final rows = await _db.customSelect(
      'SELECT * FROM ai_sessions ORDER BY updated_at DESC LIMIT ?',
      variables: <Variable<Object>>[Variable<int>(limit.clamp(1, 200))],
    ).get();
    return rows.map((row) => _sessionFromRow(row.data)).toList();
  }

  @override
  Future<void> saveMessage(AiSessionMessage message) async {
    await _db.customInsert(
      '''
      INSERT INTO ai_messages (
        id, session_id, role, content, created_at, state, citations_json,
        linked_knowledge_ids_json, feedback
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        content = excluded.content,
        state = excluded.state,
        citations_json = excluded.citations_json,
        linked_knowledge_ids_json = excluded.linked_knowledge_ids_json,
        feedback = excluded.feedback
      ''',
      variables: <Variable<Object>>[
        Variable<String>(message.id),
        Variable<String>(message.sessionId),
        Variable<String>(message.role),
        Variable<String>(message.content),
        Variable<int>(message.createdAt.millisecondsSinceEpoch),
        Variable<String>(message.state.name),
        Variable<String>(message.citationsJson),
        Variable<String>(message.linkedKnowledgeIdsJson),
        Variable<String>(message.feedback),
      ],
    );
  }

  @override
  Future<List<AiSessionMessage>> messagesForSession(String sessionId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM ai_messages WHERE session_id = ? ORDER BY created_at, rowid',
      variables: <Variable<Object>>[Variable<String>(sessionId)],
    ).get();
    return rows.map((row) => _messageFromRow(row.data)).toList();
  }

  @override
  Future<void> deleteSession(String id) => _db.customStatement(
        'DELETE FROM ai_sessions WHERE id = ?',
        <Object?>[id],
      );

  @override
  Future<void> clearSessions() =>
      _db.customStatement('DELETE FROM ai_sessions');

  @override
  Future<void> appendEvidence(LearningEvidence evidence) async {
    await _db.customInsert(
      '''
      INSERT OR REPLACE INTO learning_evidence (
        id, timestamp, source_type, source_id, knowledge_type, knowledge_id,
        question_type, result, error_type, response_time_ms, hint_level_used,
        confidence, metadata_json, model, prompt_version, user_confirmed
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(evidence.id),
        Variable<int>(evidence.timestamp.millisecondsSinceEpoch),
        Variable<String>(evidence.sourceType.name),
        Variable<String>(evidence.sourceId),
        Variable<String>(evidence.knowledgeType.name),
        Variable<String>(evidence.knowledgeId),
        Variable<String>(evidence.questionType),
        Variable<String>(evidence.result.name),
        Variable<String>(evidence.errorType.name),
        Variable<int>(evidence.responseTimeMs),
        Variable<int>(evidence.hintLevelUsed),
        Variable<double>(evidence.confidence.clamp(0, 1)),
        Variable<String>(evidence.metadataJson),
        Variable<String>(evidence.model),
        Variable<String>(evidence.promptVersion),
        Variable<int>(evidence.userConfirmed ? 1 : 0),
      ],
    );
  }

  @override
  Future<List<LearningEvidence>> recentEvidence({
    int limit = 200,
    DateTime? since,
  }) async {
    final sql = since == null
        ? 'SELECT * FROM learning_evidence ORDER BY timestamp DESC LIMIT ?'
        : 'SELECT * FROM learning_evidence WHERE timestamp >= ? ORDER BY timestamp DESC LIMIT ?';
    final variables = since == null
        ? <Variable<Object>>[Variable<int>(limit.clamp(1, 2000))]
        : <Variable<Object>>[
            Variable<int>(since.millisecondsSinceEpoch),
            Variable<int>(limit.clamp(1, 2000)),
          ];
    final rows = await _db.customSelect(sql, variables: variables).get();
    return rows.map((row) => _evidenceFromRow(row.data)).toList();
  }

  @override
  Future<List<LearningEvidence>> evidenceForKnowledge(
    KnowledgeType type,
    String knowledgeId, {
    int limit = 100,
  }) async {
    final rows = await _db.customSelect(
      '''SELECT * FROM learning_evidence
         WHERE knowledge_type = ? AND knowledge_id = ?
         ORDER BY timestamp DESC LIMIT ?''',
      variables: <Variable<Object>>[
        Variable<String>(type.name),
        Variable<String>(knowledgeId),
        Variable<int>(limit.clamp(1, 1000)),
      ],
    ).get();
    return rows.map((row) => _evidenceFromRow(row.data)).toList();
  }

  @override
  Future<void> saveMastery(KnowledgeMastery mastery) async {
    await _db.customInsert(
      '''
      INSERT INTO knowledge_mastery (
        knowledge_type, knowledge_id, mastery, confidence, evidence_count,
        updated_at, last_successful_recall_at, stability_days
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(knowledge_type, knowledge_id) DO UPDATE SET
        mastery = excluded.mastery,
        confidence = excluded.confidence,
        evidence_count = excluded.evidence_count,
        updated_at = excluded.updated_at,
        last_successful_recall_at = excluded.last_successful_recall_at,
        stability_days = excluded.stability_days
      ''',
      variables: <Variable<Object>>[
        Variable<String>(mastery.knowledgeType.name),
        Variable<String>(mastery.knowledgeId),
        Variable<double>(mastery.mastery),
        Variable<double>(mastery.confidence),
        Variable<int>(mastery.evidenceCount),
        Variable<int>(mastery.updatedAt.millisecondsSinceEpoch),
        Variable<int>(mastery.lastSuccessfulRecallAt?.millisecondsSinceEpoch),
        Variable<double>(mastery.stabilityDays),
      ],
    );
  }

  @override
  Future<List<KnowledgeMastery>> allMastery() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM knowledge_mastery ORDER BY mastery, confidence DESC',
        )
        .get();
    return rows.map((row) => _masteryFromRow(row.data)).toList();
  }

  @override
  Future<void> clearLearningInferences() async {
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM knowledge_mastery');
      await _db.customStatement(
        'DELETE FROM learning_evidence WHERE user_confirmed = 0',
      );
    });
  }

  @override
  Future<void> saveDiagnosis(DiagnosisSnapshot snapshot) async {
    await _db.customInsert(
      '''INSERT OR REPLACE INTO diagnosis_snapshots (
        id, created_at, data_window_days, data_sufficiency, weak_areas_json,
        narrative, prompt_version
      ) VALUES (?, ?, ?, ?, ?, ?, ?)''',
      variables: <Variable<Object>>[
        Variable<String>(snapshot.id),
        Variable<int>(snapshot.createdAt.millisecondsSinceEpoch),
        Variable<int>(snapshot.dataWindowDays),
        Variable<String>(snapshot.dataSufficiency.name),
        Variable<String>(snapshot.weakAreasJson),
        Variable<String>(snapshot.narrative),
        Variable<String>(snapshot.promptVersion),
      ],
    );
  }

  @override
  Future<List<DiagnosisSnapshot>> recentDiagnoses({int limit = 10}) async {
    final rows = await _db.customSelect(
      'SELECT * FROM diagnosis_snapshots ORDER BY created_at DESC LIMIT ?',
      variables: <Variable<Object>>[Variable<int>(limit.clamp(1, 100))],
    ).get();
    return rows.map((row) => _diagnosisFromRow(row.data)).toList();
  }

  @override
  Future<void> clearDiagnoses() =>
      _db.customStatement('DELETE FROM diagnosis_snapshots');

  @override
  Future<void> savePlan(StudyPlan plan) async {
    await _db.transaction(() async {
      await _db.customInsert(
        '''INSERT INTO study_plans (
          id, title, created_at, updated_at, target_minutes, status
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title,
          updated_at = excluded.updated_at,
          target_minutes = excluded.target_minutes,
          status = excluded.status''',
        variables: <Variable<Object>>[
          Variable<String>(plan.id),
          Variable<String>(plan.title),
          Variable<int>(plan.createdAt.millisecondsSinceEpoch),
          Variable<int>(plan.updatedAt.millisecondsSinceEpoch),
          Variable<int>(plan.targetMinutes),
          Variable<String>(plan.status.name),
        ],
      );
      await _db.customStatement(
        'DELETE FROM study_plan_items WHERE plan_id = ?',
        <Object?>[plan.id],
      );
      for (final item in plan.items) {
        await _db.customInsert(
          '''INSERT INTO study_plan_items (
            id, plan_id, kind, title, estimated_minutes, item_order, status,
            reason, route, payload_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          variables: <Variable<Object>>[
            Variable<String>(item.id),
            Variable<String>(item.planId),
            Variable<String>(item.kind.name),
            Variable<String>(item.title),
            Variable<int>(item.estimatedMinutes),
            Variable<int>(item.order),
            Variable<String>(item.status.name),
            Variable<String>(item.reason),
            Variable<String>(item.route),
            Variable<String>(item.payloadJson),
          ],
        );
      }
    });
  }

  @override
  Future<StudyPlan?> activePlan() async {
    final rows = await _db
        .customSelect(
          "SELECT * FROM study_plans WHERE status = 'active' ORDER BY updated_at DESC LIMIT 1",
        )
        .get();
    return rows.isEmpty ? null : _planFromRow(rows.first.data);
  }

  @override
  Future<StudyPlan?> planById(String id) async {
    final rows = await _db.customSelect(
      'SELECT * FROM study_plans WHERE id = ? LIMIT 1',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    return rows.isEmpty ? null : _planFromRow(rows.first.data);
  }

  Future<StudyPlan> _planFromRow(Map<String, Object?> data) async {
    final id = data['id'] as String;
    final itemRows = await _db.customSelect(
      'SELECT * FROM study_plan_items WHERE plan_id = ? ORDER BY item_order',
      variables: <Variable<Object>>[Variable<String>(id)],
    ).get();
    return StudyPlan(
      id: id,
      title: data['title'] as String,
      createdAt: _date(data['created_at']),
      updatedAt: _date(data['updated_at']),
      targetMinutes: _int(data['target_minutes']),
      status: _enumByName(
        StudyPlanStatus.values,
        data['status'],
        StudyPlanStatus.active,
      ),
      items: itemRows.map((row) => _planItemFromRow(row.data)).toList(),
    );
  }

  @override
  Future<void> updatePlanItemStatus(
    String itemId,
    StudyPlanItemStatus status,
  ) async {
    await _db.transaction(() async {
      await _db.customStatement(
        'UPDATE study_plan_items SET status = ? WHERE id = ?',
        <Object?>[status.name, itemId],
      );
      await _db.customStatement(
        '''UPDATE study_plans SET updated_at = ? WHERE id = (
          SELECT plan_id FROM study_plan_items WHERE id = ?
        )''',
        <Object?>[DateTime.now().millisecondsSinceEpoch, itemId],
      );
    });
  }

  @override
  Future<void> clearPlans() => _db.transaction(() async {
        await _db.customStatement('DELETE FROM study_plan_items');
        await _db.customStatement('DELETE FROM study_plans');
      });

  @override
  Future<void> saveNote(AiLearningNote note) async {
    await _db.customInsert(
      '''INSERT INTO ai_notes (
        id, title, body, source, language, course_path, tags_json,
        knowledge_ids_json, status, created_at, updated_at, next_review_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        body = excluded.body,
        source = excluded.source,
        language = excluded.language,
        course_path = excluded.course_path,
        tags_json = excluded.tags_json,
        knowledge_ids_json = excluded.knowledge_ids_json,
        status = excluded.status,
        updated_at = excluded.updated_at,
        next_review_at = excluded.next_review_at''',
      variables: <Variable<Object>>[
        Variable<String>(note.id),
        Variable<String>(note.title),
        Variable<String>(note.body),
        Variable<String>(note.source),
        Variable<String>(note.language),
        Variable<String>(note.coursePath),
        Variable<String>(note.tagsJson),
        Variable<String>(note.knowledgeIdsJson),
        Variable<String>(note.status.name),
        Variable<int>(note.createdAt.millisecondsSinceEpoch),
        Variable<int>(note.updatedAt.millisecondsSinceEpoch),
        Variable<int>(note.nextReviewAt?.millisecondsSinceEpoch),
      ],
    );
  }

  @override
  Future<List<AiLearningNote>> searchNotes(
    String query, {
    int limit = 100,
  }) async {
    final q = query.trim().toLowerCase();
    final rows = await _db
        .customSelect(
          q.isEmpty
              ? 'SELECT * FROM ai_notes ORDER BY updated_at DESC LIMIT ?'
              : '''SELECT * FROM ai_notes
               WHERE LOWER(title) LIKE ? OR LOWER(body) LIKE ? OR LOWER(tags_json) LIKE ?
               ORDER BY updated_at DESC LIMIT ?''',
          variables: q.isEmpty
              ? <Variable<Object>>[Variable<int>(limit.clamp(1, 500))]
              : <Variable<Object>>[
                  Variable<String>('%$q%'),
                  Variable<String>('%$q%'),
                  Variable<String>('%$q%'),
                  Variable<int>(limit.clamp(1, 500)),
                ],
        )
        .get();
    return rows.map((row) => _noteFromRow(row.data)).toList();
  }

  @override
  Future<void> deleteNote(String id) => _db.customStatement(
        'DELETE FROM ai_notes WHERE id = ?',
        <Object?>[id],
      );

  @override
  Future<void> clearNotes() => _db.customStatement('DELETE FROM ai_notes');

  @override
  Future<void> recordMetric(AiRequestMetric metric) => _db.customInsert(
        '''INSERT OR REPLACE INTO ai_request_metrics (
          request_id, feature, session_id, prompt_version, model, started_at,
          latency_ms, input_tokens, output_tokens, cache_hit, outcome,
          estimated_cost
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        variables: <Variable<Object>>[
          Variable<String>(metric.requestId),
          Variable<String>(metric.feature),
          Variable<String>(metric.sessionId),
          Variable<String>(metric.promptVersion),
          Variable<String>(metric.model),
          Variable<int>(metric.startedAt.millisecondsSinceEpoch),
          Variable<int>(metric.latencyMs),
          Variable<int>(metric.inputTokens),
          Variable<int>(metric.outputTokens),
          Variable<int>(metric.cacheHit ? 1 : 0),
          Variable<String>(metric.outcome.name),
          Variable<double>(metric.estimatedCost),
        ],
      );

  @override
  Future<AiUsageSummary> usageSummary({
    required DateTime since,
    String? feature,
  }) async {
    final rows = await _db.customSelect(
      // Token sums exclude cache hits: a cache-hit metric carries the ORIGINAL
      // request's tokens (not real spend), so counting them would inflate the
      // daily budget (AiBudgetManager) and the displayed total. `requests` /
      // `cache_hits` / `failures` still count every row.
      '''SELECT COUNT(*) AS requests,
         COALESCE(SUM(CASE WHEN cache_hit = 0 THEN input_tokens ELSE 0 END), 0) AS input_tokens,
         COALESCE(SUM(CASE WHEN cache_hit = 0 THEN output_tokens ELSE 0 END), 0) AS output_tokens,
         COALESCE(SUM(cache_hit), 0) AS cache_hits,
         COALESCE(SUM(CASE WHEN outcome != 'success' THEN 1 ELSE 0 END), 0) AS failures,
         COALESCE(SUM(estimated_cost), 0) AS estimated_cost
         FROM ai_request_metrics
         WHERE started_at >= ? ${feature == null ? '' : 'AND feature = ?'}''',
      variables: <Variable<Object>>[
        Variable<int>(since.millisecondsSinceEpoch),
        if (feature != null) Variable<String>(feature),
      ],
    ).get();
    final data = rows.single.data;
    return AiUsageSummary(
      requests: _int(data['requests']),
      inputTokens: _int(data['input_tokens']),
      outputTokens: _int(data['output_tokens']),
      cacheHits: _int(data['cache_hits']),
      failures: _int(data['failures']),
      estimatedCost: _double(data['estimated_cost']),
    );
  }

  @override
  Future<void> clearMetrics() =>
      _db.customStatement('DELETE FROM ai_request_metrics');

  Future<void> clearAllCompanionData() async {
    await _db.transaction(() async {
      for (final table in <String>[
        'ai_messages',
        'ai_sessions',
        'learning_evidence',
        'knowledge_mastery',
        'diagnosis_snapshots',
        'study_plan_items',
        'study_plans',
        'ai_notes',
        'ai_request_metrics',
      ]) {
        await _db.customStatement('DELETE FROM $table');
      }
    });
  }

  AiSession _sessionFromRow(Map<String, Object?> d) => AiSession(
        id: d['id'] as String,
        mode: _enumByName(AiSessionMode.values, d['mode'], AiSessionMode.qa),
        title: d['title'] as String,
        language: d['language'] as String,
        goalId: d['goal_id'] as String?,
        sourceContext: _jsonMap(d['source_context_json']),
        createdAt: _date(d['created_at']),
        updatedAt: _date(d['updated_at']),
        summary: (d['summary'] as String?) ?? '',
        status: _enumByName(
          AiSessionStatus.values,
          d['status'],
          AiSessionStatus.active,
        ),
        promptVersion: (d['prompt_version'] as String?) ?? '',
        model: (d['model'] as String?) ?? '',
        totalTokens: _int(d['total_tokens']),
        estimatedCost: _double(d['estimated_cost']),
      );

  AiSessionMessage _messageFromRow(Map<String, Object?> d) => AiSessionMessage(
        id: d['id'] as String,
        sessionId: d['session_id'] as String,
        role: d['role'] as String,
        content: (d['content'] as String?) ?? '',
        createdAt: _date(d['created_at']),
        state: _enumByName(
          AiMessageState.values,
          d['state'],
          AiMessageState.complete,
        ),
        citations: _jsonMapList(d['citations_json']),
        linkedKnowledgeIds: _jsonStringList(d['linked_knowledge_ids_json']),
        feedback: d['feedback'] as String?,
      );

  LearningEvidence _evidenceFromRow(Map<String, Object?> d) => LearningEvidence(
        id: d['id'] as String,
        timestamp: _date(d['timestamp']),
        sourceType: _enumByName(
          LearningEvidenceSource.values,
          d['source_type'],
          LearningEvidenceSource.lesson,
        ),
        sourceId: d['source_id'] as String,
        knowledgeType: _enumByName(
          KnowledgeType.values,
          d['knowledge_type'],
          KnowledgeType.unresolved,
        ),
        knowledgeId: d['knowledge_id'] as String,
        questionType: d['question_type'] as String?,
        result: _enumByName(
          LearningResult.values,
          d['result'],
          LearningResult.skipped,
        ),
        errorType: _enumByName(
          LearningErrorType.values,
          d['error_type'],
          LearningErrorType.unknown,
        ),
        responseTimeMs: _nullableInt(d['response_time_ms']),
        hintLevelUsed: _int(d['hint_level_used']),
        confidence: _double(d['confidence']),
        metadata: _jsonMap(d['metadata_json']),
        model: d['model'] as String?,
        promptVersion: d['prompt_version'] as String?,
        userConfirmed: _int(d['user_confirmed']) == 1,
      );

  KnowledgeMastery _masteryFromRow(Map<String, Object?> d) => KnowledgeMastery(
        knowledgeType: _enumByName(
          KnowledgeType.values,
          d['knowledge_type'],
          KnowledgeType.unresolved,
        ),
        knowledgeId: d['knowledge_id'] as String,
        mastery: _double(d['mastery']),
        confidence: _double(d['confidence']),
        evidenceCount: _int(d['evidence_count']),
        updatedAt: _date(d['updated_at']),
        lastSuccessfulRecallAt: _nullableDate(d['last_successful_recall_at']),
        stabilityDays: _double(d['stability_days']),
      );

  DiagnosisSnapshot _diagnosisFromRow(Map<String, Object?> d) {
    final weak = <DiagnosisWeakAreaEvidence>[];
    final raw = _jsonList(d['weak_areas_json']);
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      weak.add(DiagnosisWeakAreaEvidence(
        knowledgeId: (m['knowledgeId'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        severity: (m['severity'] ?? 'low').toString(),
        confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
        evidenceIds: (m['evidenceIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList(),
        recommendedAction: (m['recommendedAction'] ?? '').toString(),
        estimatedMinutes: (m['estimatedMinutes'] as num?)?.toInt() ?? 0,
      ));
    }
    return DiagnosisSnapshot(
      id: d['id'] as String,
      createdAt: _date(d['created_at']),
      dataWindowDays: _int(d['data_window_days']),
      dataSufficiency: _enumByName(
        DiagnosisDataSufficiency.values,
        d['data_sufficiency'],
        DiagnosisDataSufficiency.low,
      ),
      weakAreas: weak,
      narrative: (d['narrative'] as String?) ?? '',
      promptVersion: (d['prompt_version'] as String?) ?? '',
    );
  }

  StudyPlanItem _planItemFromRow(Map<String, Object?> d) => StudyPlanItem(
        id: d['id'] as String,
        planId: d['plan_id'] as String,
        kind: _enumByName(
          StudyPlanItemKind.values,
          d['kind'],
          StudyPlanItemKind.lesson,
        ),
        title: d['title'] as String,
        estimatedMinutes: _int(d['estimated_minutes']),
        order: _int(d['item_order']),
        status: _enumByName(
          StudyPlanItemStatus.values,
          d['status'],
          StudyPlanItemStatus.pending,
        ),
        reason: (d['reason'] as String?) ?? '',
        route: d['route'] as String?,
        payloadJson: (d['payload_json'] as String?) ?? '{}',
      );

  AiLearningNote _noteFromRow(Map<String, Object?> d) => AiLearningNote(
        id: d['id'] as String,
        title: d['title'] as String,
        body: d['body'] as String,
        source: d['source'] as String,
        language: d['language'] as String?,
        coursePath: d['course_path'] as String?,
        tags: _jsonStringList(d['tags_json']),
        knowledgeIds: _jsonStringList(d['knowledge_ids_json']),
        status: _enumByName(
          AiNoteStatus.values,
          d['status'],
          AiNoteStatus.pendingVerification,
        ),
        createdAt: _date(d['created_at']),
        updatedAt: _date(d['updated_at']),
        nextReviewAt: _nullableDate(d['next_review_at']),
      );

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    final name = raw?.toString();
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static DateTime _date(Object? raw) =>
      DateTime.fromMillisecondsSinceEpoch(_int(raw));
  static DateTime? _nullableDate(Object? raw) =>
      raw == null ? null : DateTime.fromMillisecondsSinceEpoch(_int(raw));
  static int _int(Object? raw) => (raw as num?)?.toInt() ?? 0;
  static int? _nullableInt(Object? raw) => (raw as num?)?.toInt();
  static double _double(Object? raw) => (raw as num?)?.toDouble() ?? 0;

  static dynamic _decode(Object? raw, dynamic fallback) {
    if (raw is! String || raw.isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static Map<String, dynamic> _jsonMap(Object? raw) {
    final value = _decode(raw, const <String, dynamic>{});
    return value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
  }

  static List<dynamic> _jsonList(Object? raw) {
    final value = _decode(raw, const <dynamic>[]);
    return value is List ? value : const <dynamic>[];
  }

  static List<String> _jsonStringList(Object? raw) =>
      _jsonList(raw).map((e) => e.toString()).toList();

  static List<Map<String, dynamic>> _jsonMapList(Object? raw) => _jsonList(raw)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
