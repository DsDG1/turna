import 'dart:convert';

enum AiSessionMode { qa, sentenceCheck, roleplay, hint, diagnosis }

enum AiSessionStatus { active, completed, archived }

enum AiMessageState { pending, streaming, complete, partial, failed }

class AiSession {
  const AiSession({
    required this.id,
    required this.mode,
    required this.title,
    required this.language,
    required this.createdAt,
    required this.updatedAt,
    this.goalId,
    this.sourceContext = const <String, dynamic>{},
    this.summary = '',
    this.status = AiSessionStatus.active,
    this.promptVersion = '',
    this.model = '',
    this.totalTokens = 0,
    this.estimatedCost = 0,
  });

  final String id;
  final AiSessionMode mode;
  final String title;
  final String language;
  final String? goalId;
  final Map<String, dynamic> sourceContext;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String summary;
  final AiSessionStatus status;
  final String promptVersion;
  final String model;
  final int totalTokens;
  final double estimatedCost;

  AiSession copyWith({
    AiSessionMode? mode,
    String? title,
    String? language,
    String? goalId,
    Map<String, dynamic>? sourceContext,
    DateTime? updatedAt,
    String? summary,
    AiSessionStatus? status,
    String? promptVersion,
    String? model,
    int? totalTokens,
    double? estimatedCost,
  }) =>
      AiSession(
        id: id,
        mode: mode ?? this.mode,
        title: title ?? this.title,
        language: language ?? this.language,
        goalId: goalId ?? this.goalId,
        sourceContext: sourceContext ?? this.sourceContext,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        summary: summary ?? this.summary,
        status: status ?? this.status,
        promptVersion: promptVersion ?? this.promptVersion,
        model: model ?? this.model,
        totalTokens: totalTokens ?? this.totalTokens,
        estimatedCost: estimatedCost ?? this.estimatedCost,
      );

  static String newId() => 'ais_${DateTime.now().microsecondsSinceEpoch}';
}

class AiSessionMessage {
  const AiSessionMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.state = AiMessageState.complete,
    this.citations = const <Map<String, dynamic>>[],
    this.linkedKnowledgeIds = const <String>[],
    this.feedback,
  });

  final String id;
  final String sessionId;
  final String role;
  final String content;
  final DateTime createdAt;
  final AiMessageState state;
  final List<Map<String, dynamic>> citations;
  final List<String> linkedKnowledgeIds;
  final String? feedback;

  AiSessionMessage copyWith({
    String? content,
    AiMessageState? state,
    List<Map<String, dynamic>>? citations,
    List<String>? linkedKnowledgeIds,
    String? feedback,
  }) =>
      AiSessionMessage(
        id: id,
        sessionId: sessionId,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        state: state ?? this.state,
        citations: citations ?? this.citations,
        linkedKnowledgeIds: linkedKnowledgeIds ?? this.linkedKnowledgeIds,
        feedback: feedback ?? this.feedback,
      );

  String get citationsJson => jsonEncode(citations);
  String get linkedKnowledgeIdsJson => jsonEncode(linkedKnowledgeIds);

  static String newId() => 'aim_${DateTime.now().microsecondsSinceEpoch}';
}
