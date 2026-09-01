import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';

/// The post-import receipt segment, shared verbatim by the main-isolate
/// inline fallback and the worker `commitReceipt` command (crash-hunt PR1).
///
/// This is the heaviest catalog work of the whole import chain — one
/// `anki_source_cards` row per card plus a descriptor page per 200 notes —
/// and it used to run as synchronous sqlite3 on the UI isolate (device ANR:
/// input dispatch timeout, process kill). Both callers must keep running
/// exactly this sequence so the crash-recovery phases stay identical.
///
/// Returns the number of card descriptors written.
Future<int> officialAnkiRunCommitReceipt({
  required OfficialAnkiImportAttemptDao attempts,
  required OfficialAnkiDatabase catalog,
  required OfficialAnkiEngine engine,
  required String attemptId,
  required String sourceId,
  required List<int> noteIds,
  required int nowMillis,
}) async {
  attempts.replaceNoteIds(attemptId: attemptId, noteIds: noteIds);
  final descriptors = <OfficialAnkiCardDescriptor>[];
  var offset = 0;
  const batchSize = 200;
  while (true) {
    final batch = attempts.noteIdPage(attemptId, offset, batchSize);
    if (batch.isEmpty) break;
    final noteCards = await engine.getNoteCardsBatch(batch);
    final cardIds = noteCards.values.expand((ids) => ids).toList();
    if (cardIds.isNotEmpty) {
      descriptors.addAll(await engine.getCardDescriptorsBatch(cardIds));
    }
    offset += batch.length;
  }
  attempts.commitIndexBatch(
    attemptId: attemptId,
    sourceId: sourceId,
    cards: descriptors,
    nextOffset: offset,
    nowMillis: nowMillis,
  );
  OfficialAnkiSourceMetadataDao(catalog).replaceAssociations(
    sourceId: sourceId,
    cards: descriptors,
  );
  attempts.setPhase(
    attemptId: attemptId,
    phase: OfficialAnkiAttemptPhase.receiptCommitted,
    nowMillis: nowMillis,
  );
  return descriptors.length;
}
