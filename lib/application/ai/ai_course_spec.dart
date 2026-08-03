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
    this.groundedMode = false,
    this.resourceScope = const ['words', 'expressions', 'grammarPoints'],
    this.maxGroundedResources = 200,
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

  /// When true, the AI is grounded to reuse existing course resources instead of
  /// inventing new ones. Mirrors tool-gui design-panel grounding.
  final bool groundedMode;

  /// Which resource types to include in the grounded context:
  /// words, expressions, grammarPoints.
  final List<String> resourceScope;

  /// Cap on how many resources to inject into the prompt.
  final int maxGroundedResources;

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
    bool? groundedMode,
    List<String>? resourceScope,
    int? maxGroundedResources,
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
        groundedMode: groundedMode ?? this.groundedMode,
        resourceScope: resourceScope ?? this.resourceScope,
        maxGroundedResources: maxGroundedResources ?? this.maxGroundedResources,
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
/// `Map<String, dynamic>` matching the Turna section file schema.
class AiGeneratedCourse {
  const AiGeneratedCourse({required this.rawJson, required this.parsed});

  final String rawJson;
  final Map<String, dynamic> parsed;
}
