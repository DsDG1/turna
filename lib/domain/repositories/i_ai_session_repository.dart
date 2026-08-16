import 'package:turna/domain/ai_companion/ai_session.dart';

abstract interface class IAiSessionRepository {
  Future<void> saveSession(AiSession session);
  Future<AiSession?> sessionById(String id);
  Future<AiSession?> latestActiveSession({AiSessionMode? mode});
  Future<List<AiSession>> recentSessions({int limit = 20});
  Future<void> saveMessage(AiSessionMessage message);
  Future<List<AiSessionMessage>> messagesForSession(String sessionId);
  Future<void> deleteSession(String id);
  Future<void> clearSessions();
}
