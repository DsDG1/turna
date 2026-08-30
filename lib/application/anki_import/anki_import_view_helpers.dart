import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';

/// Pure view formatting for the official import flow. Business judgments
/// (recognition triage, error mapping) live in the application layer:
/// `recognition/official_recognition_triage.dart` and
/// `official_import_error_messages.dart`.

/// "填空 · auto" — archetype chip label plus the recognizer's band.
String officialRecognitionChipLabel(OfficialAnkiMappingSuggestion suggestion) {
  final archetype = cardArchetypeLabel(suggestion.cardArchetype);
  final band = recognitionBandFor(suggestion.recognitionConfidence);
  final bandLabel = switch (band) {
    RecognitionBand.auto => 'auto',
    RecognitionBand.review => AppStrings.ankiRecognitionBandReview,
    RecognitionBand.fallback => AppStrings.ankiRecognitionBandFallback,
  };
  return '$archetype · $bandLabel';
}

/// Human-readable evidence lines for the preview's expandable "why" box.
List<String> officialRecognitionEvidenceLines(
  OfficialAnkiMappingSuggestion suggestion,
) {
  return [
    for (final candidate in suggestion.candidates)
      if (candidate.role != FieldRole.ignored)
        '${_roleLabel(candidate.role)}: ${candidate.fieldName}'
            '${candidate.confidence > 0 ? '（${(candidate.confidence * 100).round()}%）' : ''}'
            '${candidate.evidence.isEmpty ? '' : ' ← ${candidate.evidence.join(', ')}'}',
  ];
}

String _roleLabel(FieldRole role) {
  return switch (role) {
    FieldRole.prompt => AppStrings.ankiFieldRolePrompt,
    FieldRole.response => AppStrings.ankiFieldRoleResponse,
    FieldRole.options => AppStrings.ankiFieldRoleOptions,
    FieldRole.audio => AppStrings.ankiFieldRoleAudio,
    FieldRole.image => AppStrings.ankiFieldRoleImage,
    FieldRole.pronunciation => AppStrings.ankiFieldRolePronunciation,
    FieldRole.example => AppStrings.ankiFieldRoleExample,
    FieldRole.hint => AppStrings.ankiFieldRoleHint,
    FieldRole.extra => AppStrings.ankiFieldRoleExtra,
    FieldRole.unitLabel => AppStrings.ankiFieldRoleUnit,
    FieldRole.lessonLabel => AppStrings.ankiFieldRoleLesson,
    FieldRole.ignored => AppStrings.ankiFieldRoleIgnored,
  };
}

/// Short preview of one Anki field for the import list (no HTML, no
/// jargon).
String importSamplePreview(String raw, {int maxChars = 42}) {
  final plain = CardText.stripHtml(raw)
      .replaceAll(RegExp(r'\[sound:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return AppStrings.ankiMappingEmptySample;
  if (plain.length <= maxChars) return plain;
  return '${plain.substring(0, maxChars)}…';
}

String userFacingFieldName(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'front':
    case '正面':
      return AppStrings.ankiFieldNameFront;
    case 'back':
    case '反面':
    case '背面':
      return AppStrings.ankiFieldNameBack;
    case 'text':
      return AppStrings.ankiFieldNameText;
    case 'extra':
    case 'back extra':
      return AppStrings.ankiFieldNameExtra;
    case 'occlusion':
      return AppStrings.ankiFieldNameOcclusion;
    case 'image':
      return AppStrings.ankiFieldNameImage;
    case 'audio':
      return AppStrings.ankiFieldNameAudio;
    default:
      return raw;
  }
}
