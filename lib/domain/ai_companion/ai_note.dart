import 'dart:convert';

enum AiNoteStatus { stillLearning, understood, pendingVerification, mastered }

class AiLearningNote {
  const AiLearningNote({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.language,
    this.coursePath,
    this.tags = const <String>[],
    this.knowledgeIds = const <String>[],
    this.status = AiNoteStatus.pendingVerification,
    this.nextReviewAt,
  });

  final String id;
  final String title;
  final String body;
  final String source;
  final String? language;
  final String? coursePath;
  final List<String> tags;
  final List<String> knowledgeIds;
  final AiNoteStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? nextReviewAt;

  String get tagsJson => jsonEncode(tags);
  String get knowledgeIdsJson => jsonEncode(knowledgeIds);
}
