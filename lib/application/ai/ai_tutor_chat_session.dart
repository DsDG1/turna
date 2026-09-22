// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Prefs key for the single tutor-chat transcript.
const kTutorChatSessionKey = 'ai.tutorChat.session';

/// One persisted tutor-chat session (mode name, language, durable messages).
class AiTutorChatSession {
  const AiTutorChatSession({
    required this.modeName,
    required this.language,
    required this.messages,
  });

  final String modeName;
  final String language;
  final List<AiChatMessage> messages;

  bool get isEmpty => messages.isEmpty;

  Map<String, dynamic> toJson() => {
        'mode': modeName,
        'language': language,
        'messages': [
          for (final message in messages)
            {'role': message.role, 'content': message.content},
        ],
      };

  static AiTutorChatSession? fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    if (rawMessages is! List) return null;
    final messages = <AiChatMessage>[];
    for (final entry in rawMessages) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final content = (map['content'] ?? '').toString();
      if (content.trim().isEmpty) continue;
      messages.add(AiChatMessage(
        role: (map['role'] ?? 'user').toString(),
        content: content,
      ));
    }
    if (messages.isEmpty) return null;
    return AiTutorChatSession(
      modeName: (json['mode'] ?? 'qa').toString(),
      language: (json['language'] ?? '').toString(),
      messages: messages,
    );
  }
}

/// Prefs JSON store for the tutor chat. One session, capped message list.
class AiTutorChatSessionStore {
  AiTutorChatSessionStore({AppPrefs? prefs}) : _prefs = prefs;

  static const int maxMessages = 50;

  final AppPrefs? _prefs;

  AppPrefs? get _resolved {
    if (_prefs != null) return _prefs;
    if (getIt.isRegistered<AppPrefs>()) return getIt<AppPrefs>();
    return null;
  }

  bool get hasSession => load() != null;

  AiTutorChatSession? load() {
    final prefs = _resolved;
    if (prefs == null) return null;
    try {
      final raw = prefs.preferences
          .getString(kTutorChatSessionKey, defaultValue: '')
          .getValue();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AiTutorChatSession.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Corrupt JSON — treat as no session.
      return null;
    }
  }

  Future<void> save(AiTutorChatSession session) async {
    final prefs = _resolved;
    if (prefs == null) return;
    final messages = session.messages.length > maxMessages
        ? session.messages.sublist(session.messages.length - maxMessages)
        : session.messages;
    final durable = AiTutorChatSession(
      modeName: session.modeName,
      language: session.language,
      messages: [
        for (final message in messages)
          if (message.content.trim().isNotEmpty) message,
      ],
    );
    if (durable.isEmpty) {
      await clear();
      return;
    }
    await prefs.preferences
        .setString(kTutorChatSessionKey, jsonEncode(durable.toJson()));
  }

  Future<void> clear() async {
    final prefs = _resolved;
    if (prefs == null) return;
    await prefs.preferences.remove(kTutorChatSessionKey);
  }
}
