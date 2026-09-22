// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Prefs key for the tutor-chat transcript list.
const kTutorChatSessionKey = 'ai.tutorChat.session';

/// One persisted tutor-chat session (mode name, language, durable messages).
class AiTutorChatSession {
  const AiTutorChatSession({
    this.id = '',
    required this.modeName,
    required this.language,
    required this.messages,
    this.updatedAt,
  });

  final String id;
  final String modeName;
  final String language;
  final List<AiChatMessage> messages;
  final DateTime? updatedAt;

  bool get isEmpty => messages.isEmpty;

  String get title {
    for (final message in messages) {
      if (message.role != 'user') continue;
      final text = message.content.trim();
      if (text.isEmpty) continue;
      return text.length > 40 ? '${text.substring(0, 40)}…' : text;
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': modeName,
        'language': language,
        'updatedAt': updatedAt?.toIso8601String(),
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
    final updatedRaw = json['updatedAt'];
    return AiTutorChatSession(
      id: (json['id'] ?? '').toString(),
      modeName: (json['mode'] ?? 'qa').toString(),
      language: (json['language'] ?? '').toString(),
      messages: messages,
      updatedAt: updatedRaw is String ? DateTime.tryParse(updatedRaw) : null,
    );
  }
}

/// Prefs JSON store for tutor chats. Keeps a short list and one active id.
class AiTutorChatSessionStore {
  AiTutorChatSessionStore({AppPrefs? prefs}) : _prefs = prefs;

  static const int maxMessages = 50;
  static const int maxSessions = 20;

  final AppPrefs? _prefs;
  int _seq = 0;

  AppPrefs? get _resolved {
    if (_prefs != null) return _prefs;
    if (getIt.isRegistered<AppPrefs>()) return getIt<AppPrefs>();
    return null;
  }

  bool get hasSession => list().isNotEmpty;

  /// Active transcript, or the newest saved one when nothing is active.
  AiTutorChatSession? load() {
    final index = _read();
    if (index == null) return null;
    if (index.activeId.isNotEmpty) {
      for (final session in index.sessions) {
        if (session.id == index.activeId) return session;
      }
      return null;
    }
    return null;
  }

  List<AiTutorChatSession> list() {
    final index = _read();
    if (index == null) return const [];
    final sessions = [...index.sessions]..sort((a, b) {
        final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
    return sessions;
  }

  AiTutorChatSession? loadById(String id) {
    for (final session in list()) {
      if (session.id == id) return session;
    }
    return null;
  }

  Future<void> save(AiTutorChatSession session) async {
    final prefs = _resolved;
    if (prefs == null) return;
    final index = _read() ?? const _SessionIndex(activeId: '', sessions: []);
    final messages = session.messages.length > maxMessages
        ? session.messages.sublist(session.messages.length - maxMessages)
        : session.messages;
    final durableMessages = [
      for (final message in messages)
        if (message.content.trim().isNotEmpty) message,
    ];
    if (durableMessages.isEmpty) {
      await _dropActive(index);
      return;
    }
    final id = session.id.isNotEmpty
        ? session.id
        : (index.activeId.isNotEmpty ? index.activeId : _newId());
    final durable = AiTutorChatSession(
      id: id,
      modeName: session.modeName,
      language: session.language,
      messages: durableMessages,
      updatedAt: DateTime.now().toUtc(),
    );
    final next = [
      for (final existing in index.sessions)
        if (existing.id != id) existing,
      durable,
    ];
    next.sort((a, b) {
      final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    final capped =
        next.length > maxSessions ? next.sublist(0, maxSessions) : next;
    await _write(_SessionIndex(activeId: id, sessions: capped));
  }

  /// Leaves saved transcripts in place and clears the active pointer so the
  /// next message starts a new session.
  Future<void> beginNew() async {
    final index = _read();
    if (index == null) return;
    await _write(_SessionIndex(activeId: '', sessions: index.sessions));
  }

  Future<void> activate(String id) async {
    final index = _read();
    if (index == null) return;
    if (!index.sessions.any((session) => session.id == id)) return;
    await _write(_SessionIndex(activeId: id, sessions: index.sessions));
  }

  Future<void> delete(String id) async {
    final index = _read();
    if (index == null) return;
    final next = [
      for (final session in index.sessions)
        if (session.id != id) session,
    ];
    final active = index.activeId == id ? '' : index.activeId;
    await _write(_SessionIndex(activeId: active, sessions: next));
  }

  Future<void> clear() async {
    final prefs = _resolved;
    if (prefs == null) return;
    await prefs.preferences.remove(kTutorChatSessionKey);
  }

  Future<void> _dropActive(_SessionIndex index) async {
    if (index.activeId.isEmpty) {
      if (index.sessions.isEmpty) {
        await clear();
      }
      return;
    }
    final next = [
      for (final session in index.sessions)
        if (session.id != index.activeId) session,
    ];
    if (next.isEmpty) {
      await clear();
      return;
    }
    await _write(_SessionIndex(activeId: '', sessions: next));
  }

  String _newId() => 's${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  _SessionIndex? _read() {
    final prefs = _resolved;
    if (prefs == null) return null;
    try {
      final raw = prefs.preferences
          .getString(kTutorChatSessionKey, defaultValue: '')
          .getValue();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return _SessionIndex.decode(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Corrupt JSON — treat as no session.
      return null;
    }
  }

  Future<void> _write(_SessionIndex index) async {
    final prefs = _resolved;
    if (prefs == null) return;
    if (index.sessions.isEmpty && index.activeId.isEmpty) {
      await clear();
      return;
    }
    await prefs.preferences
        .setString(kTutorChatSessionKey, jsonEncode(index.toJson()));
  }
}

class _SessionIndex {
  const _SessionIndex({required this.activeId, required this.sessions});

  final String activeId;
  final List<AiTutorChatSession> sessions;

  Map<String, dynamic> toJson() => {
        'activeId': activeId,
        'sessions': [for (final session in sessions) session.toJson()],
      };

  static _SessionIndex? decode(Map<String, dynamic> json) {
    final rawSessions = json['sessions'];
    if (rawSessions is List) {
      final sessions = <AiTutorChatSession>[];
      for (final entry in rawSessions) {
        if (entry is! Map) continue;
        final session =
            AiTutorChatSession.fromJson(Map<String, dynamic>.from(entry));
        if (session == null) continue;
        sessions.add(session.id.isEmpty
            ? AiTutorChatSession(
                id: 'legacy-${sessions.length}',
                modeName: session.modeName,
                language: session.language,
                messages: session.messages,
                updatedAt: session.updatedAt,
              )
            : session);
      }
      return _SessionIndex(
        activeId: (json['activeId'] ?? '').toString(),
        sessions: sessions,
      );
    }
    final legacy = AiTutorChatSession.fromJson(json);
    if (legacy == null) return null;
    final id = legacy.id.isEmpty ? 'legacy' : legacy.id;
    return _SessionIndex(
      activeId: id,
      sessions: [
        AiTutorChatSession(
          id: id,
          modeName: legacy.modeName,
          language: legacy.language,
          messages: legacy.messages,
          updatedAt: legacy.updatedAt ?? DateTime.now().toUtc(),
        ),
      ],
    );
  }
}
