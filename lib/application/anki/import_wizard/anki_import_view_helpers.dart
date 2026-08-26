import 'dart:io';

import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/import_wizard/notetype_mapping_util.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/l10n/app_strings.dart';

/// Shared attention levels for recognition rows (legacy + official).
enum ImportRecognitionAttention { recognized, advisory, blocking, skipped }

ImportRecognitionAttention legacyRecognitionAttention(
  LegacyAnkiImportPreviewModel preview,
  int mid,
  AnkiNotetype notetype,
) {
  final mapping = preview.mappings[mid];
  final fieldCount = notetype.fieldNames.length;
  if (mapping == null || fieldCount == 0) {
    return ImportRecognitionAttention.blocking;
  }
  if (mappingUsesFrontBackFields(mapping.type)) {
    final front = mapping.frontFieldIndex;
    final back = mapping.backFieldIndex;
    if (front < 0 || back < 0 || front >= fieldCount || back >= fieldCount) {
      return ImportRecognitionAttention.blocking;
    }
    if (fieldCount > 1 && front == back) {
      return ImportRecognitionAttention.blocking;
    }
  }
  return (preview.recognitionResults[mid]?.needsConfirmation ?? true)
      ? ImportRecognitionAttention.advisory
      : ImportRecognitionAttention.recognized;
}

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
  if (conflict ||
      missingTarget ||
      missingAnswer ||
      suggestion.status == OfficialAnkiMappingStatus.needsMapping) {
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
  if (error is AnkiImportException) {
    return error.message;
  }
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
