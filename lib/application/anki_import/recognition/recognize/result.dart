import '../config.dart' as cfg show recognizerVersion;
import '../config.dart' show bandAutoMin, bandReviewMin;
import '../lexicon/field_roles.dart' as lex show lexiconVersion;
import '../lexicon/field_roles.dart' show FieldRole;

/// The single archetype vocabulary for recognition, projection policy,
/// and UI (doc 37 §3.3) — one enum where the legacy stack kept four.
enum CardArchetype {
  /// Templates carry script/complex structure → fidelity rendering.
  richHtml,

  /// Collection declares cloze (or samples carry strong cloze evidence).
  cloze,

  /// An options structure exists (option-pool field or embedded options).
  choice,

  /// Front-side audio drives the card.
  audioFirst,

  /// Templates contain `{{type:}}`.
  typeIn,

  /// Plain front/back text pair — the universal fallback.
  basicPair,
}

/// Human-readable label for evidence UI (Chinese, matching the mapping
/// page's tone). Evidence strings themselves stay machine-stable.
String cardArchetypeLabel(CardArchetype archetype) {
  return switch (archetype) {
    CardArchetype.richHtml => '保真原卡',
    CardArchetype.cloze => '填空',
    CardArchetype.choice => '选择',
    CardArchetype.audioFirst => '听音',
    CardArchetype.typeIn => '拼写',
    CardArchetype.basicPair => '正反翻面',
  };
}

/// Confidence band for the overall recognition conclusion (§3.6).
enum RecognitionBand { auto, review, fallback }

RecognitionBand recognitionBandFor(double confidence) {
  if (confidence >= bandAutoMin) return RecognitionBand.auto;
  if (confidence >= bandReviewMin) return RecognitionBand.review;
  return RecognitionBand.fallback;
}

/// One reason the recognizer weighed in. [signal] is a stable machine key
/// (e.g. `template:typeIn`); [detail] is human-readable context.
class RecognitionEvidence {
  const RecognitionEvidence({
    required this.signal,
    required this.weight,
    this.detail = '',
    this.target,
  });

  final String signal;
  final double weight;
  final String detail;
  final CardArchetype? target;

  String describe() =>
      detail.isEmpty ? signal : '$signal ($detail)';

  Map<String, Object?> toJson() => <String, Object?>{
        'signal': signal,
        'weight': weight,
        'detail': detail,
        'target': target?.name,
      };
}

/// A field bound to a role, with the winning score and the evidence that
/// contributed to it.
class FieldBinding {
  const FieldBinding({
    required this.role,
    required this.fieldIndex,
    required this.fieldName,
    required this.confidence,
    this.evidence = const <RecognitionEvidence>[],
  });

  final FieldRole role;
  final int fieldIndex;
  final String fieldName;
  final double confidence;
  final List<RecognitionEvidence> evidence;
}

/// Notetype-level recognition conclusion: one archetype, one role binding
/// set, every conclusion traceable through [evidence].
class RecognitionResult {
  const RecognitionResult({
    required this.archetype,
    required this.confidence,
    required this.evidence,
    required this.roles,
    required this.fieldCount,
    this.templateFactsHash = '',
    this.recognizerVersion = cfg.recognizerVersion,
    this.lexiconVersion = lex.lexiconVersion,
  });

  final CardArchetype archetype;
  final double confidence;
  final List<RecognitionEvidence> evidence;
  final Map<FieldRole, FieldBinding> roles;
  final int fieldCount;

  /// Recognition-cache invalidation key (differs from the user mapping's
  /// schema fingerprint: template changes re-run recognition but never
  /// flag confirmed mappings for review).
  final String templateFactsHash;
  final int recognizerVersion;
  final int lexiconVersion;

  RecognitionBand get band => recognitionBandFor(confidence);

  /// Cloze notetypes and single-field notetypes have no back side to map.
  bool get singleField =>
      archetype == CardArchetype.cloze || fieldCount <= 1;

  FieldBinding? binding(FieldRole role) => roles[role];
}
