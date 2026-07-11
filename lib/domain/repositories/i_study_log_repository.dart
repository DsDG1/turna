// Project imports:
import 'package:varnamala/domain/study/daily_stats.dart';
import 'package:varnamala/domain/study/study_log.dart';

/// Persistence API for study activity logs and daily aggregates.
///
/// Concrete: [StudyLogRepository]. Phase 21 defines the interface only —
/// DI still registers the concrete class (see ADR 0007).
abstract class IStudyLogRepository {
  Future<void> appendLog(StudyLog log);
  Future<List<StudyLog>> readLogs({
    DateTime? since,
    DateTime? until,
    StudyActivityType? type,
  });
  Future<Map<String, DailyStudyStats>> readAllDailyStats();
  Future<List<DailyStudyStats>> readLastNDays(int n);
  Future<void> clearAll();
}
