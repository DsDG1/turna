// Project imports:
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/di/injection.dart';

/// Append an entry to the AI Hub "continue" list.
///
/// Shared by every AI provider so the advisory try/swallow semantics around
/// the getIt lookup stay identical: recent-task logging must never break the
/// feature that produced the result.
void recordAiRecentTask({
  required String kind,
  required String summary,
  AiRecentTaskRoute? route,
  DateTime? timestamp,
}) {
  try {
    getIt<AiRecentTasksProvider>().record(
      AiRecentTask(
        kind: kind,
        summary: summary,
        timestamp: timestamp ?? DateTime.now(),
        route: route,
      ),
    );
  } catch (_) {
    // Advisory only.
  }
}
