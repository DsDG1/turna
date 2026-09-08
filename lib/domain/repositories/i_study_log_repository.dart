// Project imports:
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/domain/study/study_log.dart';

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
    String? languageCode,
  });
  Future<Map<String, DailyStudyStats>> readAllDailyStats({
    String? languageCode,
  });
  Future<List<DailyStudyStats>> readLastNDays(int n, {String? languageCode});
  Future<void> clearAll();

  /// Remove one language's logs and daily aggregates (builtin uninstall
  /// path). Rows written before the language dimension count as turkish.
  Future<void> deleteByLanguage(String languageCode);
}
