// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/domain/repositories/i_ai_practice_repository.dart';

/// Drift-backed storage for the AI course library.
///
/// Two tables (see ADR 0054): `ai_courses` holds the collection the learner
/// sees (title, language, favourite, expiry) and `ai_course_versions` holds one
/// row per generation attempt. Both are intentionally outside the course tree
/// (see [db.AiCourses]): a bundled-content reseed must not delete generated
/// courses, and they must never leak into the Learn tab.
@LazySingleton(as: IAiPracticeRepository)
class AiPracticeRepository implements IAiPracticeRepository {
  AiPracticeRepository(this._db);

  final db.CourseDatabase _db;

  @override
  Future<List<AiCourse>> list({String? languageCode, int? limit}) async {
    final query = _db.select(_db.aiCourses);
    if (languageCode != null && languageCode.isNotEmpty) {
      query.where((t) => t.languageCode.equals(languageCode));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.updatedAtMs)]);
    if (limit != null && limit > 0) query.limit(limit);
    final rows = await query.get();
    if (rows.isEmpty) return const <AiCourse>[];
    final versions = await _versionsFor(rows.map((row) => row.id).toList());
    return [
      for (final row in rows) _toDomain(row, versions[row.id] ?? const []),
    ];
  }

  @override
  Future<AiCourse?> byId(String id) async {
    final row = await (_db.select(_db.aiCourses)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final versions = await _versionsFor([id]);
    return _toDomain(row, versions[id] ?? const []);
  }

  @override
  Future<void> upsertCourse(AiCourse course) async {
    await _db.into(_db.aiCourses).insertOnConflictUpdate(
          db.AiCoursesCompanion(
            id: Value(course.id),
            languageCode: Value(course.languageCode),
            title: Value(course.title),
            sourceKind: Value(course.source.name),
            level: Value(course.level),
            topic: Value(course.topic),
            pinned: Value(course.pinned),
            expiresAtMs: Value(course.expiresAt?.millisecondsSinceEpoch),
            createdAtMs: Value(course.createdAt.millisecondsSinceEpoch),
            updatedAtMs: Value(course.updatedAt.millisecondsSinceEpoch),
          ),
        );
  }

  @override
  Future<void> upsertVersion(AiCourseVersion version) async {
    await _db.into(_db.aiCourseVersions).insertOnConflictUpdate(
          db.AiCourseVersionsCompanion(
            id: Value(version.id),
            courseId: Value(version.courseId),
            status: Value(version.status.name),
            sectionJson: Value(version.sectionJson),
            requestJson: Value(version.requestJson),
            qualityJson: Value(version.qualityJson),
            progressDone: Value(version.progressDone),
            progressTotal: Value(version.progressTotal),
            errorMessage: Value(version.errorMessage),
            explanation: Value(version.explanation),
            createdAtMs: Value(version.createdAt.millisecondsSinceEpoch),
            updatedAtMs: Value(version.updatedAt.millisecondsSinceEpoch),
          ),
        );
  }

  @override
  Future<void> deleteMany(Iterable<String> ids) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) return;
    await (_db.delete(_db.aiCourseVersions)
          ..where((t) => t.courseId.isIn(idList)))
        .go();
    await (_db.delete(_db.aiCourses)..where((t) => t.id.isIn(idList))).go();
  }

  @override
  Future<void> setPinned(
    Iterable<String> ids, {
    required bool pinned,
    DateTime? now,
  }) async {
    final idList = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (idList.isEmpty) return;
    final at = now ?? DateTime.now();
    await (_db.update(_db.aiCourses)..where((t) => t.id.isIn(idList))).write(
      db.AiCoursesCompanion(
        pinned: Value(pinned),
        expiresAtMs: Value(
          pinned ? null : at.add(kAiCourseDraftTtl).millisecondsSinceEpoch,
        ),
        updatedAtMs: Value(at.millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<int> markInterruptedOnStartup() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.aiCourseVersions)
          ..where(
            (t) => t.status.isIn([
              AiPracticeStatus.queued.name,
              AiPracticeStatus.running.name,
            ]),
          ))
        .write(
      db.AiCourseVersionsCompanion(
        status: Value(AiPracticeStatus.interrupted.name),
        errorMessage: const Value('应用已关闭，生成已中断。可点击重试。'),
        updatedAtMs: Value(now),
      ),
    );
  }

  @override
  Future<int> pruneExpired({required DateTime now}) async {
    final cutoff = now.millisecondsSinceEpoch;
    final expired = await (_db.select(_db.aiCourses)
          ..where(
            (t) =>
                t.pinned.equals(false) &
                t.expiresAtMs.isNotNull() &
                t.expiresAtMs.isSmallerOrEqualValue(cutoff),
          ))
        .get();
    if (expired.isEmpty) return 0;
    final ids = expired.map((row) => row.id).toList();
    await deleteMany(ids);
    return ids.length;
  }

  /// Versions of [courseIds], grouped by course, newest first.
  Future<Map<String, List<AiCourseVersion>>> _versionsFor(
    List<String> courseIds,
  ) async {
    if (courseIds.isEmpty) return const {};
    final rows = await (_db.select(_db.aiCourseVersions)
          ..where((t) => t.courseId.isIn(courseIds))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAtMs),
            (t) => OrderingTerm.desc(t.updatedAtMs),
          ]))
        .get();
    final grouped = <String, List<AiCourseVersion>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.courseId, () => []).add(_toVersion(row));
    }
    return grouped;
  }

  AiCourse _toDomain(db.AiCourseRow row, List<AiCourseVersion> versions) =>
      AiCourse(
        id: row.id,
        languageCode: row.languageCode,
        title: row.title,
        source: AiPracticeSource.fromWire(row.sourceKind),
        level: row.level,
        topic: row.topic,
        pinned: row.pinned,
        expiresAt: row.expiresAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row.expiresAtMs!),
        versions: versions,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs),
      );

  AiCourseVersion _toVersion(db.AiCourseVersionRow row) => AiCourseVersion(
        id: row.id,
        courseId: row.courseId,
        status: AiPracticeStatus.fromWire(row.status),
        sectionJson: row.sectionJson,
        requestJson: row.requestJson,
        qualityJson: row.qualityJson,
        progressDone: row.progressDone,
        progressTotal: row.progressTotal,
        errorMessage: row.errorMessage,
        explanation: row.explanation,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtMs),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMs),
      );
}
