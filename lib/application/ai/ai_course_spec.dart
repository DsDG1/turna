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
    this.designBrief = '',
    this.groundedMode = false,
    this.resourceScope = const ['words', 'expressions', 'grammarPoints'],
    this.maxGroundedResources = 200,
    this.itemsPerLesson = 8,
    this.preferredInteractionTypes = const <String>[],
    this.focusItems = '',
    this.presetId,
  });

  /// Target language to teach (e.g. "Turkish").
  final String language;

  /// Language used for prompts / hints / translations (e.g. "Chinese",
  /// "English"). Mirrors GUI `source_language`.
  final String sourceLanguage;

  /// Free-form topic / theme (e.g. "Travel vocabulary", "Past tense").
  final String topic;

  /// CEFR level hint (e.g. "A1", "A2", "B1", "B2", "C1", "C2").
  final String level;

  /// How many units to generate.
  final int unitCount;

  /// How many lessons per unit to generate.
  final int lessonsPerUnit;

  /// Lesson template applied when not using genre batch:
  /// intro / practice / review / listening / reading / dialogue / guide /
  /// mastery / mixed.
  final String template;

  /// Enable `[genre]` tag multi-template batch generation.
  final bool useGenreBatch;

  /// Optional extra instructions appended to the prompt.
  final String extraInstructions;

  /// Course-design intent ("编排意图") carried into the outline and lesson
  /// prompts. Mirrors tool-gui's `AiCourseSpec.design_brief`.
  final String designBrief;

  /// When true, the AI is grounded to reuse existing course resources instead of
  /// inventing new ones. Mirrors tool-gui design-panel grounding.
  final bool groundedMode;

  /// Which resource types to include in the grounded context:
  /// words, expressions, grammarPoints.
  final List<String> resourceScope;

  /// Cap on how many resources to inject into the prompt.
  final int maxGroundedResources;

  /// Desired question/item count per lesson (e.g. 6 light, 10 standard,
  /// 15 intensive). Default 8 preserves prior behavior.
  final int itemsPerLesson;

  /// Optional preferred interaction runtimeTypes chosen by the learner.
  /// Empty means automatic template-appropriate mix.
  final List<String> preferredInteractionTypes;

  /// Optional learner-supplied focus vocabulary, phrases, or grammar points
  /// that the generated course must cover.
  final String focusItems;

  /// Optional preset id selected in the custom course form (informational).
  final String? presetId;

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
    String? designBrief,
    bool? groundedMode,
    List<String>? resourceScope,
    int? maxGroundedResources,
    int? itemsPerLesson,
    List<String>? preferredInteractionTypes,
    String? focusItems,
    String? presetId,
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
        designBrief: designBrief ?? this.designBrief,
        groundedMode: groundedMode ?? this.groundedMode,
        resourceScope: resourceScope ?? this.resourceScope,
        maxGroundedResources: maxGroundedResources ?? this.maxGroundedResources,
        itemsPerLesson: itemsPerLesson ?? this.itemsPerLesson,
        preferredInteractionTypes:
            preferredInteractionTypes ?? this.preferredInteractionTypes,
        focusItems: focusItems ?? this.focusItems,
        presetId: presetId ?? this.presetId,
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
