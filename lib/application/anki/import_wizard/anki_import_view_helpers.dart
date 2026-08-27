import 'dart:io';

import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki_practice/card_text.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/l10n/app_strings.dart';

/// Shared attention levels for recognition rows (official flow).
enum ImportRecognitionAttention { recognized, advisory, blocking, skipped }

ImportRecognitionAttention officialRecognitionAttention(
  OfficialAnkiImportPreviewModel preview,
  OfficialAnkiProjectionSchema schema,
) {
  final id = schema.notetypeId;
  if (preview.skippedNotetypes.contains(id)) {
    return ImportRecognitionAttention.skipped;
  }
  final suggestion = preview.suggestions[id];
  if (suggestion == null) return ImportRecognitionAttention.blocking;
  final conflict = OfficialAnkiProjectionMapper().mappingConflict(
        suggestion,
      ) !=
      null;
  final missingTarget =
      suggestion.role(OfficialAnkiFieldRole.targetText) == null;
  final missingAnswer = !suggestion.singleFieldMode &&
      suggestion.role(OfficialAnkiFieldRole.nativeText) == null;
  if (conflict) {
    return ImportRecognitionAttention.blocking;
  }
  if (missingTarget &&
      (missingAnswer ||
          suggestion.status == OfficialAnkiMappingStatus.needsMapping)) {
    return ImportRecognitionAttention.blocking;
  }
  if (preview.confirmedNotetypes.contains(id)) {
    return ImportRecognitionAttention.recognized;
  }
  if (suggestion.status == OfficialAnkiMappingStatus.needsConfirm ||
      suggestion.status == OfficialAnkiMappingStatus.needsReview) {
    return ImportRecognitionAttention.advisory;
  }
  return ImportRecognitionAttention.recognized;
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

String importAttentionStatusLabel(ImportRecognitionAttention attention) {
  switch (attention) {
    case ImportRecognitionAttention.blocking:
      return AppStrings.ankiMappingStatusBlocking;
    case ImportRecognitionAttention.advisory:
      return AppStrings.ankiMappingStatusAdvisory;
    case ImportRecognitionAttention.recognized:
      return AppStrings.ankiMappingStatusRecognized;
    case ImportRecognitionAttention.skipped:
      return AppStrings.ankiOfficialMappingSkipped;
  }
}

/// Short preview of one Anki field for the import list (no HTML, no jargon).
String importSamplePreview(String raw, {int maxChars = 42}) {
  final plain = CardText.stripHtml(raw)
      .replaceAll(RegExp(r'\[sound:[^\]]+\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return AppStrings.ankiMappingEmptySample;
  if (plain.length <= maxChars) return plain;
  return '${plain.substring(0, maxChars)}…';
}

String officialGuessedTypeLabel({
  required OfficialAnkiProjectionSchema schema,
  OfficialAnkiMappingSuggestion? suggestion,
}) {
  if (schema.kind == 'cloze' ||
      schema.name.toLowerCase().contains('cloze') ||
      schema.samples.any((s) => s.fields.any((f) => f.contains('{{c')))) {
    return AppStrings.ankiQuestionTypeFillBlank;
  }
  final name = schema.name.toLowerCase();
  if (name.contains('occlusion') || name.contains('遮图')) {
    return AppStrings.ankiQuestionTypeFlip;
  }
  if (suggestion != null &&
      suggestion.candidates
          .any((c) => c.role == OfficialAnkiFieldRole.optionPool)) {
    return AppStrings.ankiQuestionTypeChoice;
  }
  return AppStrings.ankiQuestionTypeFlip;
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
