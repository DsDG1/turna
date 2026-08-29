import 'dart:io';

import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';

/// Recognition triage for preview rows (doc 37 §4). The old four-level
/// `ImportRecognitionAttention` enum is gone: blocking now comes from
/// broken bindings (no prompt field, missing back side, conflicts), and
/// "advisory" is exactly the recognizer's review band.
class OfficialRecognitionTriage {
  const OfficialRecognitionTriage({
    required this.blocking,
    required this.advisory,
    required this.skipped,
  });

  final bool blocking;
  final bool advisory;
  final bool skipped;

  bool get recognized => !blocking && !advisory && !skipped;
}

OfficialRecognitionTriage officialRecognitionTriage(
  OfficialAnkiImportPreviewModel preview,
  OfficialAnkiProjectionSchema schema,
) {
  final id = schema.notetypeId;
  if (preview.skippedNotetypes.contains(id)) {
    return const OfficialRecognitionTriage(
      blocking: false,
      advisory: false,
      skipped: true,
    );
  }
  final suggestion = preview.suggestions[id];
  if (suggestion == null) {
    return const OfficialRecognitionTriage(
      blocking: true,
      advisory: false,
      skipped: false,
    );
  }
  final conflict = officialAnkiMappingConflict(suggestion) != null;
  final missingPrompt = suggestion.role(FieldRole.prompt) == null;
  final missingResponse =
      !suggestion.singleFieldMode && suggestion.role(FieldRole.response) == null;
  final blocking = conflict || missingPrompt || missingResponse;
  final advisory = !blocking && suggestion.status == OfficialAnkiMappingStatus.review;
  return OfficialRecognitionTriage(
    blocking: blocking,
    advisory: advisory,
    skipped: false,
  );
}

/// Error → human message mappers shared by the page (§10.7: no duplicate
/// error mapping left in the widget).
String mapOfficialErrorToHuman(OfficialAnkiException e) {
  if (e.code == OfficialAnkiErrorCode.packageInvalid ||
      e.code == OfficialAnkiErrorCode.collectionCorrupt) {
    return AppStrings.ankiCorruptDeck;
  }
  if (e.code == OfficialAnkiErrorCode.packageNotFound ||
      e.code == OfficialAnkiErrorCode.ioError) {
    return AppStrings.ankiFileReadFailed;
  }
  if (e.code == OfficialAnkiErrorCode.unsupportedPlatform ||
      e.code == OfficialAnkiErrorCode.contractVersionMismatch) {
    return AppStrings.ankiPickFileError;
  }
  return '\${AppStrings.ankiImportFailedHuman} (\${e.code.name})';
}

String mapGeneralErrorToHuman(Object error) {
  if (error is FileSystemException || error is IOException) {
    return AppStrings.ankiFileReadFailed;
  }
  final msg = error.toString();
  if (msg.contains('.colpkg')) {
    return AppStrings.ankiColpkgUnsupported;
  }
  if (msg.contains('.apkg')) {
    return AppStrings.ankiPickFileError;
  }
  return AppStrings.ankiParseFailed(error);
}

/// "填空 · auto" — archetype chip label plus the recognizer's band.
String officialRecognitionChipLabel(OfficialAnkiMappingSuggestion suggestion) {
  final archetype = cardArchetypeLabel(suggestion.cardArchetype);
  final band = recognitionBandFor(suggestion.recognitionConfidence);
  final bandLabel = switch (band) {
    RecognitionBand.auto => 'auto',
    RecognitionBand.review => '建议确认',
    RecognitionBand.fallback => '需确认',
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
    FieldRole.prompt => '正面',
    FieldRole.response => '背面',
    FieldRole.options => '选项',
    FieldRole.audio => '音频',
    FieldRole.image => '图片',
    FieldRole.pronunciation => '读音',
    FieldRole.example => '例句',
    FieldRole.hint => '提示',
    FieldRole.extra => '补充',
    FieldRole.unitLabel => '单元',
    FieldRole.lessonLabel => '课时',
    FieldRole.ignored => '未用',
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
      return '正面';
    case 'back':
    case '反面':
    case '背面':
      return '背面';
    case 'text':
      return '正文';
    case 'extra':
    case 'back extra':
      return '补充';
    case 'occlusion':
      return '遮挡图';
    case 'image':
      return '图片';
    case 'audio':
      return '音频';
    default:
      return raw;
  }
}
