import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// The v2 card-index segment, shared verbatim by the main-isolate inline
/// fallback and the worker `v2CardIndex` command (ADR 0044 R1.5).
///
/// One `anki_source_cards` row per card is the heaviest v2 catalog write of
/// the commit chain, and it used to run as synchronous sqlite3 on the UI
/// isolate — the same ANR class crash-hunt fixed for v1's `commitReceipt`.
/// Both callers must keep running exactly this sequence so the crash
/// recovery phases stay identical (kill mid-segment → attempt stays in
/// `committing`, census resumes by intent).
///
/// Returns the number of card descriptors written.
Future<int> officialAnkiV2RunCardIndex({
  required OfficialAnkiSourceDao sources,
  required OfficialAnkiImportAttemptDao attempts,
  required OfficialAnkiEngine engine,
  required String attemptId,
  required String sourceId,
}) async {
  final noteIds = attempts.receiptNoteIds(attemptId);
  final descriptors = <OfficialAnkiCardDescriptor>[];
  for (var offset = 0; offset < noteIds.length; offset += 200) {
    final batch = noteIds.skip(offset).take(200).toList();
    final noteCards = await engine.getNoteCardsBatch(batch);
    final cardIds = noteCards.values.expand((ids) => ids).toList();
    if (cardIds.isNotEmpty) {
      descriptors.addAll(await engine.getCardDescriptorsBatch(cardIds));
    }
  }
  sources.upsertCardBatch(sourceId: sourceId, cards: descriptors);
  return descriptors.length;
}
