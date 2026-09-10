import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

/// L0: structural facts about a notetype, extracted from the contract
/// schema + derived templateFacts. Pure data — no heuristics here.
class NotetypeFacts {
  NotetypeFacts({
    required this.notetypeId,
    required this.name,
    required this.fieldNames,
    required this.isClozeKind,
    required this.templates,
    required this.reqs,
    required this.templateFactsHash,
    required this.hasTemplateFacts,
    required this.samples,
  });

  final int notetypeId;
  final String name;
  final List<String> fieldNames;
  final bool isClozeKind;

  /// Per-template face facts derived by the engine (empty when talking to
  /// a pre-1.9 backend — `hasTemplateFacts` false).
  final List<OfficialAnkiTemplateFact> templates;
  final List<OfficialAnkiCardRequirement> reqs;
  final String templateFactsHash;
  final bool hasTemplateFacts;

  /// Sample note field values aligned with [fieldNames].
  final List<List<String>> samples;

  factory NotetypeFacts.fromSchema(OfficialAnkiProjectionSchema schema) {
    final facts = schema.templateFacts;
    return NotetypeFacts(
      notetypeId: schema.notetypeId,
      name: schema.name,
      fieldNames: schema.fieldNames,
      isClozeKind: schema.kind == 'cloze',
      templates: facts?.templates ?? const <OfficialAnkiTemplateFact>[],
      reqs: facts?.reqs ?? const <OfficialAnkiCardRequirement>[],
      templateFactsHash: facts?.hash ?? '',
      hasTemplateFacts: facts?.isAvailable ?? false,
      samples: [
        for (final sample in schema.samples)
          sample.fields.take(schema.fieldNames.length).toList(),
      ],
    );
  }

  /// Field ords referenced on some template's front face.
  Set<int> get frontFieldOrds => <int>{
        for (final template in templates)
          ...template.frontFields,
      };

  /// Field ords referenced on back faces only.
  Set<int> get backOnlyFieldOrds {
    final front = frontFieldOrds;
    final back = <int>{
      for (final template in templates) ...template.backFields,
    };
    return back.difference(front);
  }

  /// Field names referenced through `{{tts:}}` filters.
  Set<String> get ttsFieldNames => <String>{
        for (final template in templates) ...template.tts,
      };

  /// Any template declares `{{type:}}`.
  bool get hasTypeInFilter =>
      templates.any((template) => template.typeIn);

  /// Any template face carries script/event-handler/JS structure.
  bool get hasTemplateScript =>
      templates.any((template) => template.script);

  /// Any template face carries complex HTML structure (table/svg/…).
  bool get hasTemplateComplexHtml =>
      templates.any((template) => template.complexHtml);

  /// Non-empty sample values of a field (aligned by index).
  List<String> nonEmptySamplesOf(int fieldIndex) {
    return [
      for (final values in samples)
        if (fieldIndex < values.length && values[fieldIndex].trim().isNotEmpty)
          values[fieldIndex],
    ];
  }

  /// Row-paired values of two fields (front/answer). Rows without the
  /// first field's value drop out; an empty second value stays and
  /// counts as unaligned — [nonEmptySamplesOf] on both sides separately
  /// would silently break the row pairing.
  List<(String, String)> pairedSamplesOf(int fieldIndex, int pairedFieldIndex) {
    return [
      for (final values in samples)
        if (fieldIndex < values.length &&
            values[fieldIndex].trim().isNotEmpty)
          (
            values[fieldIndex],
            pairedFieldIndex < values.length
                ? values[pairedFieldIndex]
                : '',
          ),
    ];
  }
}
