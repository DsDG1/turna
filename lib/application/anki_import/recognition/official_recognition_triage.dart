import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';

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
  if (preview.confirmedNotetypes.contains(id)) {
    return const OfficialRecognitionTriage(
      blocking: false,
      advisory: false,
      skipped: false,
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

/// Recalculates the preview banner: any remaining blocking (unconfirmed,
/// unskipped) notetype keeps [OfficialAnkiImportPreviewModel.needsMapping].
void refreshOfficialPreviewNeedsMapping(
  OfficialAnkiImportPreviewModel preview,
) {
  preview.needsMapping = preview.schemas.any(
    (schema) => officialRecognitionTriage(preview, schema).blocking,
  );
}
