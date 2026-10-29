/// The declarative adaptation plan (ADR 0057 §7).
///
/// This is the only shape AI is allowed to produce: layout, field bindings and
/// exercise choices. It never carries scripts, network calls, file paths or
/// template source — those are rejected at parse time, not executed later.
///
/// Field names and values here are *references*; the card itself stays the
/// single source of truth.
library;

/// Vocabulary the validator and the AI schema share. Adding a presentation or
/// block kind means adding it here first, so an unknown name cannot slip
/// through as "just a string".
abstract final class AdaptationVocabulary {
  static const int schemaVersion = 1;

  /// Layout blocks the app can actually render today.
  static const Set<String> blockKinds = <String>{
    'text',
    'imageGroup',
    'audioGroup',
    'richText',
  };

  /// Exercise kinds the resolver can select. `imageRecall` and `dictation` are
  /// opt-in (ADR 0057 §9), but a plan may name them.
  static const Set<String> exerciseKinds = <String>{
    'flip',
    'imageRecall',
    'dictation',
    'listenPick',
    'typeAnswer',
    'multipleChoice',
    'multiSelect',
    'fillBlank',
    'translate',
  };

  /// Field roles a plan may bind. Mirrors the recognition vocabulary minus the
  /// internal-only entries.
  static const Set<String> bindingRoles = <String>{
    'prompt',
    'answer',
    'pronunciation',
    'example',
    'audio',
    'image',
    'options',
  };

  /// What happens when the plan cannot be applied. `original` is the only
  /// fallback the app promises; anything else is a lie about capability.
  static const Set<String> fallbacks = <String>{'original'};

  /// Block selections: every extracted occurrence, or just the first.
  static const Set<String> selections = <String>{'all', 'first'};
}

/// Raised when a reply is not a plan at all (missing/ill-typed envelope).
class AdaptationPlanFormatException implements Exception {
  const AdaptationPlanFormatException(this.code, [this.detail = '']);

  final String code;
  final String detail;

  @override
  String toString() =>
      'AdaptationPlanFormatException($code${detail.isEmpty ? '' : ': $detail'})';
}

/// Where a plan applies: one source, one notetype, one template identity.
///
/// Cloze keeps its target separate from the template ordinal: a cloze card's
/// ordinal points at the deletion number, not at a normal template index
/// (ADR 0057 §3).
class AdaptationScope {
  const AdaptationScope({
    required this.sourceId,
    required this.notetypeId,
    required this.templateOrdinal,
    this.clozeTarget,
  });

  final String sourceId;
  final int notetypeId;
  final int templateOrdinal;
  final int? clozeTarget;

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceId': sourceId,
        'notetypeId': notetypeId,
        'templateOrdinal': templateOrdinal,
        if (clozeTarget != null) 'clozeTarget': clozeTarget,
      };

  factory AdaptationScope.fromJson(Map<String, Object?> json) {
    final sourceId = json['sourceId'];
    final notetypeId = json['notetypeId'];
    final template = json['templateOrdinal'];
    if (sourceId is! String || sourceId.isEmpty) {
      throw const AdaptationPlanFormatException('scope_source');
    }
    if (notetypeId is! num) {
      throw const AdaptationPlanFormatException('scope_notetype');
    }
    if (template is! num) {
      throw const AdaptationPlanFormatException('scope_template');
    }
    final cloze = json['clozeTarget'];
    return AdaptationScope(
      sourceId: sourceId,
      notetypeId: notetypeId.toInt(),
      templateOrdinal: template.toInt(),
      clozeTarget: cloze is num ? cloze.toInt() : null,
    );
  }
}

/// One ordered block of a face. Blocks only reference which field to read and
/// how; they never inline the field's content.
class AdaptationBlock {
  const AdaptationBlock({
    required this.kind,
    required this.fieldIndex,
    this.selection = 'all',
  });

  final String kind;
  final int fieldIndex;
  final String selection;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'fieldIndex': fieldIndex,
        'selection': selection,
      };

  factory AdaptationBlock.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    final fieldIndex = json['fieldIndex'];
    if (kind is! String) {
      throw const AdaptationPlanFormatException('block_kind');
    }
    if (fieldIndex is! num) {
      throw const AdaptationPlanFormatException('block_field');
    }
    final selection = json['selection'];
    return AdaptationBlock(
      kind: kind,
      fieldIndex: fieldIndex.toInt(),
      selection: selection is String ? selection : 'all',
    );
  }
}

/// A validated-ish plan. [AdaptationPlanValidator] decides whether it may be
/// activated; parsing only guarantees the envelope is present.
class CardAdaptationPlan {
  const CardAdaptationPlan({
    required this.planId,
    required this.revision,
    required this.scope,
    required this.bindings,
    required this.front,
    required this.back,
    this.defaultExercise = 'flip',
    this.schemaVersion = AdaptationVocabulary.schemaVersion,
    this.optionalExercises = const <String>[],
    this.fallback = 'original',
    this.origin = 'aiCandidate',
    this.fingerprints = const <String, Object?>{},
    this.provenance = const <String, Object?>{},
  });

  final String planId;
  final int revision;
  final AdaptationScope scope;

  /// Role name → field index (the role names come from
  /// [AdaptationVocabulary.bindingRoles]).
  final Map<String, int> bindings;

  final List<AdaptationBlock> front;
  final List<AdaptationBlock> back;

  /// The exercise every card in scope starts with; [optionalExercises] are the
  /// extras the learner may pick. Kept separate from layout: changing the
  /// exercise changes the task, changing the layout does not (plan §10).
  final String defaultExercise;
  final List<String> optionalExercises;
  final String fallback;
  final String origin;
  final Map<String, Object?> fingerprints;
  final Map<String, Object?> provenance;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'planId': planId,
        'revision': revision,
        'scope': scope.toJson(),
        'bindings': bindings,
        'front': [for (final block in front) block.toJson()],
        'back': [for (final block in back) block.toJson()],
        'defaultExercise': defaultExercise,
        'optionalExercises': optionalExercises,
        'fallback': fallback,
        'origin': origin,
        'fingerprints': fingerprints,
        'provenance': provenance,
      };

  factory CardAdaptationPlan.fromJson(Map<String, Object?> json) {
    final planId = json['planId'];
    final revision = json['revision'];
    final scope = json['scope'];
    final front = json['front'];
    if (planId is! String || planId.isEmpty) {
      throw const AdaptationPlanFormatException('plan_id');
    }
    if (revision is! num) {
      throw const AdaptationPlanFormatException('plan_revision');
    }
    if (scope is! Map) {
      throw const AdaptationPlanFormatException('plan_scope');
    }
    if (front is! List) {
      throw const AdaptationPlanFormatException('plan_front');
    }

    final rawBindings = json['bindings'];
    final bindings = <String, int>{};
    if (rawBindings is Map) {
      for (final entry in rawBindings.entries) {
        final value = entry.value;
        if (value is num) bindings['${entry.key}'] = value.toInt();
      }
    }

    List<AdaptationBlock> blocks(Object? raw) => <AdaptationBlock>[
          if (raw is List)
            for (final item in raw)
              if (item is Map)
                AdaptationBlock.fromJson(Map<String, Object?>.from(item)),
        ];

    final exercises = json['optionalExercises'];
    final schemaVersion = json['schemaVersion'];
    return CardAdaptationPlan(
      planId: planId,
      revision: revision.toInt(),
      scope: AdaptationScope.fromJson(Map<String, Object?>.from(scope)),
      bindings: bindings,
      front: blocks(front),
      back: blocks(json['back']),
      defaultExercise: json['defaultExercise'] is String
          ? json['defaultExercise'] as String
          : 'flip',
      optionalExercises: exercises is List
          ? [for (final item in exercises) '$item']
          : const <String>[],
      fallback: json['fallback'] is String ? json['fallback'] as String : 'original',
      origin: json['origin'] is String ? json['origin'] as String : 'aiCandidate',
      fingerprints: json['fingerprints'] is Map
          ? Map<String, Object?>.from(json['fingerprints'] as Map)
          : const <String, Object?>{},
      provenance: json['provenance'] is Map
          ? Map<String, Object?>.from(json['provenance'] as Map)
          : const <String, Object?>{},
      schemaVersion: schemaVersion is num
          ? schemaVersion.toInt()
          : AdaptationVocabulary.schemaVersion,
    );
  }
}
