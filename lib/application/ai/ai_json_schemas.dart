/// JSON Schemas handed to `response_format: {type: json_schema}`.
///
/// **Why this file exists.** `AiEngine.requestJson` has always accepted a
/// `jsonSchema`, `AiHttpClient.resolveResponseFormat` has always known how to
/// send it, and the 400 -> `json_object` fallback has always been ready — but
/// no caller ever passed one, so `json_schema` was never put on the wire and
/// the Settings three-way toggle (`auto` / `on` / `off`) collapsed to a single
/// behaviour. These schemas close that gap.
///
/// **Shape policy.** Each schema pins the *envelope* (top-level keys the parser
/// reads) and leaves the interior loose (`additionalProperties: true`,
/// `strict: false`). Two reasons:
///   * the parsers tolerate and normalize extra fields, so over-constraining
///     would cause valid replies to be rejected by the provider;
///   * nested lesson content varies per template, so a fully closed schema
///     would have to encode every template's runtime shape — far more surface
///     area than the benefit is worth.
///
/// A provider that refuses `json_schema` entirely is handled upstream: with
/// [StrictSchemaMode.auto] the client retries once as `json_object` and
/// remembers the probe per Base URL.
abstract final class AiJsonSchemas {
  /// Wrap a raw schema object in the OpenAI `json_schema` envelope.
  static Map<String, dynamic> _envelope(
    String name,
    Map<String, dynamic> schema,
  ) =>
      {
        'name': name,
        'strict': false,
        'schema': {
          'additionalProperties': true,
          ...schema,
        },
      };

  static Map<String, dynamic> _object({
    required String name,
    required Map<String, dynamic> properties,
    required List<String> required,
  }) =>
      _envelope(name, {
        'type': 'object',
        'properties': properties,
        'required': required,
      });

  /// Learning diagnosis (`DiagnosisReport.fromJson`).
  static final Map<String, dynamic> diagnosis = _object(
    name: 'learning_diagnosis',
    properties: {
      'weakAreas': {'type': 'array'},
      'priorityTips': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'exampleDrillIdeas': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    required: ['weakAreas', 'priorityTips'],
  );

  /// Dictionary enrichment (`DictionaryEnrichment.fromJson`).
  static final Map<String, dynamic> dictionary = _object(
    name: 'dictionary_enrichment',
    properties: {
      'term': {'type': 'string'},
      'expandedGloss': {'type': 'string'},
      'examples': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'pairs': {'type': 'array'},
      'mnemonic': {'type': 'string'},
    },
    required: ['expandedGloss'],
  );

  /// Course / practice **outline** phase (`AiPracticePipeline.validateOutline`).
  ///
  /// Only `id` and `units` are pinned; `units[].lessons[].template` is validated
  /// afterwards by the pipeline, which produces a readable error and a repair
  /// round-trip rather than a provider-side rejection.
  static final Map<String, dynamic> courseOutline = _object(
    name: 'course_outline',
    properties: {
      'id': {'type': 'string'},
      'name': {'type': 'string'},
      'description': {'type': 'string'},
      'words': {'type': 'array'},
      'expressions': {'type': 'array'},
      'grammarPoints': {'type': 'array'},
      'units': {
        'type': 'array',
        'items': {'type': 'object'},
      },
    },
    required: ['id', 'units'],
  );

  /// One lesson body in the per-lesson fill phase.
  ///
  /// `content` is pinned as an object but deliberately not enumerated: its
  /// required members differ per template (`subLessons` / `stages` /
  /// `listeningPhases` / `readingPassage`), and `normalizeLessonJson` already
  /// repairs the near-miss shapes.
  static final Map<String, dynamic> lessonBody = _object(
    name: 'lesson_body',
    properties: {
      'id': {'type': 'string'},
      'name': {'type': 'string'},
      'description': {'type': 'string'},
      'template': {'type': 'string'},
      'content': {'type': 'object'},
    },
    required: ['content'],
  );

  /// Textbook knowledge extraction (`coerceKnowledgePoints`).
  static final Map<String, dynamic> knowledgePoints = _object(
    name: 'textbook_knowledge',
    properties: {
      'words': {'type': 'array'},
      'expressions': {'type': 'array'},
      'grammarPoints': {'type': 'array'},
    },
    required: ['words'],
  );

  /// Card adaptation plan (ADR 0057 §7, `AiCardAdaptationService`).
  ///
  /// Only the envelope is pinned. `bindings`, block contents and exercises are
  /// validated by `AdaptationPlanValidator` after parsing, because a JSON
  /// Schema cannot express "the answer field must not appear on the front" and
  /// a provider-side rejection would tell the user nothing actionable.
  static final Map<String, dynamic> cardAdaptation = _object(
    name: 'card_adaptation_plan',
    properties: {
      'schemaVersion': {'type': 'integer'},
      'planId': {'type': 'string'},
      'revision': {'type': 'integer'},
      'bindings': {'type': 'object'},
      'front': {
        'type': 'array',
        'items': {'type': 'object'},
      },
      'back': {
        'type': 'array',
        'items': {'type': 'object'},
      },
      'optionalExercises': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'defaultExercise': {'type': 'string'},
      'fallback': {'type': 'string'},
    },
    required: ['planId', 'revision', 'bindings', 'front', 'back'],
  );
}
