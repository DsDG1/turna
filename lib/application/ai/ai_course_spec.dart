/// Parameters describing the course the user wants the AI to author.
///
/// Mirrors `tool/gui/src/backend/ai_generator.py:AiCourseSpec`.
class AiCourseSpec {
  const AiCourseSpec({
    required this.language,
    this.sourceLanguage = 'Chinese',
    required this.topic,
    required this.level,
    required this.unitCount,
    required this.lessonsPerUnit,
    this.template = 'mixed',
    this.useGenreBatch = false,
    this.extraInstructions = '',
  });

  /// Target language to teach (e.g. "Turkish").
  final String language;

  /// Language used for prompts / hints / translations (e.g. "Chinese",
  /// "English"). Mirrors GUI `source_language`.
  final String sourceLanguage;

  /// Free-form topic / theme (e.g. "Travel vocabulary", "Past tense").
  final String topic;

  /// CEFR level hint (e.g. "A1", "A2", "B1").
  final String level;

  /// How many units to generate.
  final int unitCount;

  /// How many lessons per unit to generate.
  final int lessonsPerUnit;

  /// Lesson template applied when not using genre batch:
  /// intro / practice / review / listening / reading / mastery / mixed.
  final String template;

  /// Enable `[genre]` tag multi-template batch generation.
  final bool useGenreBatch;

  /// Optional extra instructions appended to the prompt.
  final String extraInstructions;

  AiCourseSpec copyWith({
    String? language,
    String? sourceLanguage,
    String? topic,
    String? level,
    int? unitCount,
    int? lessonsPerUnit,
    String? template,
    bool? useGenreBatch,
    String? extraInstructions,
  }) =>
      AiCourseSpec(
        language: language ?? this.language,
        sourceLanguage: sourceLanguage ?? this.sourceLanguage,
        topic: topic ?? this.topic,
        level: level ?? this.level,
        unitCount: unitCount ?? this.unitCount,
        lessonsPerUnit: lessonsPerUnit ?? this.lessonsPerUnit,
        template: template ?? this.template,
        useGenreBatch: useGenreBatch ?? this.useGenreBatch,
        extraInstructions: extraInstructions ?? this.extraInstructions,
      );
}

/// A single message in the wish-mode conversation.
class AiChatMessage {
  const AiChatMessage({
    this.role = 'user',
    required this.content,
    this.timestamp,
  });

  final String role;
  final String content;
  final String? timestamp;

  Map<String, dynamic> toApiDict() => {'role': role, 'content': content};
}

/// A course JSON payload produced by the AI, already decoded into a
/// `Map<String, dynamic>` matching the Varnamala section file schema.
class AiGeneratedCourse {
  const AiGeneratedCourse({required this.rawJson, required this.parsed});

  final String rawJson;
  final Map<String, dynamic> parsed;
}