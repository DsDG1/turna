import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

/// One persisted field→role assignment. Role names use the recognition
/// vocabulary; rows written by older builds parse through the legacy
/// name map in `field_roles.dart`.
class OfficialAnkiFieldCandidate {
  const OfficialAnkiFieldCandidate({
    required this.role,
    required this.fieldIndex,
    required this.fieldName,
    required this.confidence,
    required this.evidence,
  });

  final FieldRole role;
  final int fieldIndex;
  final String fieldName;
  final double confidence;
  final List<String> evidence;
}

/// Mapping trust states, collapsed from the old five
/// (autoCandidate/needsConfirm/needsMapping/needsReview/skipped):
/// - auto: recognizer high confidence, untouched
/// - review: recognizer wants a human look (review/fallback band)
/// - manual: the user took ownership (confirmed or edited)
/// - skipped: the user excluded this notetype from exercises
enum OfficialAnkiMappingStatus { auto, review, manual, skipped }

const Map<String, OfficialAnkiMappingStatus> _legacyStatusNames = {
  'autoCandidate': OfficialAnkiMappingStatus.auto,
  'needsConfirm': OfficialAnkiMappingStatus.review,
  'needsMapping': OfficialAnkiMappingStatus.review,
  'needsReview': OfficialAnkiMappingStatus.review,
};

OfficialAnkiMappingStatus mappingStatusFromName(String name) {
  if (_legacyStatusNames.containsKey(name)) return _legacyStatusNames[name]!;
  return OfficialAnkiMappingStatus.values.firstWhere(
    (value) => value.name == name,
    orElse: () => OfficialAnkiMappingStatus.review,
  );
}

class OfficialAnkiMappingSuggestion {
  const OfficialAnkiMappingSuggestion({
    required this.candidates,
    required this.status,
    this.notetypeId = 0,
    this.schemaFingerprint = '',
    this.mappingVersion = 1,
    this.userConfirmed = false,
    this.updatedAtMillis = 0,
    this.enabledKinds = const <String>[
      'showWord',
      'flip',
      'multipleChoice',
      'multiSelect',
      'listenPick',
      'typeAnswer',
      'fillBlank',
      'canonicalLink',
    ],
    this.singleFieldMode = false,
    this.direction = 'promptToResponse',
    this.archetype = 'basicPair',
    this.recognitionConfidence = 0,
    this.recognizerVersion = 0,
    this.lexiconVersion = 0,
    this.templateFactsHash = '',
  });

  final List<OfficialAnkiFieldCandidate> candidates;
  final OfficialAnkiMappingStatus status;
  final int notetypeId;
  final String schemaFingerprint;
  final int mappingVersion;
  final bool userConfirmed;
  final int updatedAtMillis;
  final List<String> enabledKinds;
  final bool singleFieldMode;
  final String direction;

  /// Recognition provenance (doc 37 §3.3): which archetype produced this
  /// suggestion and how strongly. `recognizerVersion`/`lexiconVersion` of
  /// 0 marks a legacy row written before the recognizer existed.
  final String archetype;
  final double recognitionConfidence;
  final int recognizerVersion;
  final int lexiconVersion;
  final String templateFactsHash;

  CardArchetype get cardArchetype => CardArchetype.values.firstWhere(
        (value) => value.name == archetype,
        orElse: () => CardArchetype.basicPair,
      );

  OfficialAnkiFieldCandidate? role(FieldRole role) {
    final matches = candidates.where((c) => c.role == role).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return matches.isEmpty ? null : matches.first;
  }

  OfficialAnkiMappingSuggestion copyWith({
    List<OfficialAnkiFieldCandidate>? candidates,
    OfficialAnkiMappingStatus? status,
    int? notetypeId,
    String? schemaFingerprint,
    int? mappingVersion,
    bool? userConfirmed,
    int? updatedAtMillis,
    List<String>? enabledKinds,
    bool? singleFieldMode,
    String? direction,
    String? archetype,
    double? recognitionConfidence,
    int? recognizerVersion,
    int? lexiconVersion,
    String? templateFactsHash,
  }) {
    return OfficialAnkiMappingSuggestion(
      candidates: candidates ?? this.candidates,
      status: status ?? this.status,
      notetypeId: notetypeId ?? this.notetypeId,
      schemaFingerprint: schemaFingerprint ?? this.schemaFingerprint,
      mappingVersion: mappingVersion ?? this.mappingVersion,
      userConfirmed: userConfirmed ?? this.userConfirmed,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      enabledKinds: enabledKinds ?? this.enabledKinds,
      singleFieldMode: singleFieldMode ?? this.singleFieldMode,
      direction: direction ?? this.direction,
      archetype: archetype ?? this.archetype,
      recognitionConfidence:
          recognitionConfidence ?? this.recognitionConfidence,
      recognizerVersion: recognizerVersion ?? this.recognizerVersion,
      lexiconVersion: lexiconVersion ?? this.lexiconVersion,
      templateFactsHash: templateFactsHash ?? this.templateFactsHash,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'status': status.name,
        'notetypeId': notetypeId,
        'schemaFingerprint': schemaFingerprint,
        'mappingVersion': mappingVersion,
        'userConfirmed': userConfirmed,
        'updatedAtMillis': updatedAtMillis,
        'enabledKinds': enabledKinds,
        'singleFieldMode': singleFieldMode,
        'direction': direction,
        'archetype': archetype,
        'recognitionConfidence': recognitionConfidence,
        'recognizerVersion': recognizerVersion,
        'lexiconVersion': lexiconVersion,
        'templateFactsHash': templateFactsHash,
        'candidates': candidates
            .map(
              (c) => <String, Object?>{
                'role': c.role.name,
                'fieldIndex': c.fieldIndex,
                'fieldName': c.fieldName,
                'confidence': c.confidence,
                'evidence': c.evidence,
              },
            )
            .toList(),
      };

  factory OfficialAnkiMappingSuggestion.fromJson(Map<String, Object?> json) {
    final raw = json['candidates'];
    final statusName = json['status'] as String? ?? 'review';
    final kinds = json['enabledKinds'];
    final direction = json['direction'] as String? ?? 'promptToResponse';
    return OfficialAnkiMappingSuggestion(
      status: mappingStatusFromName(statusName),
      notetypeId: (json['notetypeId'] as num?)?.toInt() ?? 0,
      schemaFingerprint: json['schemaFingerprint'] as String? ?? '',
      mappingVersion: (json['mappingVersion'] as num?)?.toInt() ?? 1,
      userConfirmed: json['userConfirmed'] == true,
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
      enabledKinds: kinds is List
          ? kinds.map((e) => e.toString()).toList()
          : const <String>[
              'flip',
              'multipleChoice',
              'listenPick',
              'typeAnswer',
              'canonicalLink',
            ],
      singleFieldMode: json['singleFieldMode'] == true,
      direction: direction == 'targetToNative'
          ? 'promptToResponse'
          : (direction == 'nativeToTarget' ? 'responseToPrompt' : direction),
      archetype:
          json['archetype'] as String? ?? CardArchetype.basicPair.name,
      recognitionConfidence:
          (json['recognitionConfidence'] as num?)?.toDouble() ?? 0,
      recognizerVersion: (json['recognizerVersion'] as num?)?.toInt() ?? 0,
      lexiconVersion: (json['lexiconVersion'] as num?)?.toInt() ?? 0,
      templateFactsHash: json['templateFactsHash'] as String? ?? '',
      candidates: raw is List
          ? raw.whereType<Map>().map((item) {
              final map = Map<String, Object?>.from(item);
              return OfficialAnkiFieldCandidate(
                role: fieldRoleFromName(map['role'] as String? ?? 'ignored'),
                fieldIndex: (map['fieldIndex'] as num?)?.toInt() ?? 0,
                fieldName: map['fieldName'] as String? ?? '',
                confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
                evidence: (map['evidence'] as List? ?? const [])
                    .map((e) => e.toString())
                    .toList(),
              );
            }).toList()
          : const <OfficialAnkiFieldCandidate>[],
    );
  }
}

/// Guard for user edits: prompt and response may not share a field
/// (single-field/cloze notetypes are exempt).
String? officialAnkiMappingConflict(OfficialAnkiMappingSuggestion suggestion) {
  final prompt = suggestion.role(FieldRole.prompt);
  final response = suggestion.role(FieldRole.response);
  if (prompt != null &&
      response != null &&
      prompt.fieldIndex == response.fieldIndex &&
      !suggestion.singleFieldMode) {
    return 'prompt_response_same_field';
  }
  return null;
}

/// Bridge from a notetype-level recognition result to the persisted
/// suggestion shape: bindings become candidates, the band becomes the
/// status, and recognition provenance rides along (doc 37 §5 — preview
/// computes this fresh, confirmed rows are never touched by it).
OfficialAnkiMappingSuggestion officialAnkiSuggestMapping(
  OfficialAnkiProjectionSchema schema, [
  CardRecognizer recognizer = const CardRecognizer(),
]) {
  final result = recognizer.recognizeNotetype(schema);
  final boundIndices = result.roles.values
      .map((binding) => binding.fieldIndex)
      .toSet();
  return OfficialAnkiMappingSuggestion(
    candidates: [
      for (final binding in result.roles.values)
        OfficialAnkiFieldCandidate(
          role: binding.role,
          fieldIndex: binding.fieldIndex,
          fieldName: binding.fieldName,
          confidence: binding.confidence,
          evidence: [
            for (final item in binding.evidence) item.describe(),
          ],
        ),
      // Fields the solver could not place stay visible in the editor as
      // ignored candidates (one candidate per field, as before).
      for (var i = 0; i < schema.fieldNames.length; i++)
        if (!boundIndices.contains(i))
          OfficialAnkiFieldCandidate(
            role: FieldRole.ignored,
            fieldIndex: i,
            fieldName: schema.fieldNames[i],
            confidence: 0.2,
            evidence: const ['unmatched'],
          ),
    ],
    status: result.band == RecognitionBand.auto
        ? OfficialAnkiMappingStatus.auto
        : OfficialAnkiMappingStatus.review,
    notetypeId: schema.notetypeId,
    schemaFingerprint: schema.schemaFingerprint,
    singleFieldMode: result.singleField,
    archetype: result.archetype.name,
    recognitionConfidence: result.confidence,
    recognizerVersion: result.recognizerVersion,
    lexiconVersion: result.lexiconVersion,
    templateFactsHash: result.templateFactsHash,
  );
}
