// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/import/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';

/// Removes every persisted resource belonging to one Anki import.
///
/// This is the SINGLE uninstall saga — `AnkiDeckManager.uninstallDeck` and
/// the import wizard's rollback both delegate here, so a step added for one
/// caller cannot be missed by the other (that drift previously leaked deck
/// index / issue / projection rows on every uninstall).
class AnkiImportCleanupService {
  final ICourseRepository repository;
  final SrsProvider srsProvider;
  final AnkiImportDao importDao;
  final AnkiNoteDao noteDao;
  final ReviewHistoryDao? reviewHistoryDao;
  final AnkiAudioResolver audioResolver;
  final AnkiUnificationDao? unificationDao;
  final MistakeProvider? mistakeProvider;

  /// Used to release the media player's file handles before media files are
  /// deleted. Optional so tests and non-UI callers can omit it.
  final AudioController? audioController;

  const AnkiImportCleanupService({
    required this.repository,
    required this.srsProvider,
    required this.importDao,
    required this.noteDao,
    this.reviewHistoryDao,
    required this.audioResolver,
    this.unificationDao,
    this.mistakeProvider,
    this.audioController,
  });

  Future<void> deleteAll(String importId) async {
    await repository.deleteByTag('anki:$importId');
    final sections = await repository.sectionShells();
    for (final section in sections) {
      if (!section.id.startsWith('official-anki-') &&
          LegacyAnkiIdentifiers.importIdFromSectionId(section.id) == importId) {
        await repository.deleteSection(section.id);
      }
    }
    final prefix = 'anki-$importId-';
    await srsProvider.removeByPrefix(prefix);
    await reviewHistoryDao?.deleteByCardPrefix(prefix);
    await unificationDao?.deleteByCourseId(
      CardIntroductionEligibility.courseIdForLegacyImport(importId),
    );
    await noteDao.deleteByImport(importId);
    await noteDao.deletePrerenderedByPrefix(prefix);
    await _deleteMediaBestEffort(importId);
    await importDao.delete(importId);
    await mistakeProvider?.removeForAnkiDeletion(idPrefixes: [prefix]);
    // Defense in depth: the dedup authority is the persisted inventory, but
    // the orchestrator's in-process caches (placements, presentations, SRS
    // ids, in-flight keys) must also be retired so a same-process re-import
    // of this package is never mistaken for "already imported".
    UnifiedAnkiImportOrchestrator.instance.invalidate(importId: importId);
  }

  /// Media deletion is best-effort and must never abort the saga: a file
  /// still held by the audio player or a WebView stays on disk, the import
  /// record is still deleted below, and the leftover directory becomes an
  /// owner-less orphan that the startup sweep retries once the lock is gone.
  /// Without this, one locked file used to interrupt [deleteAll] after the
  /// course tree was already gone — the deck vanished from the UI with no
  /// retry entry while its files remained.
  Future<void> _deleteMediaBestEffort(String importId) async {
    try {
      await audioController?.stopSpeechPlayer();
    } catch (e) {
      debugPrint(
        '[AnkiImportCleanupService] stopSpeechPlayer failed '
        'for $importId: $e',
      );
    }
    final report = await audioResolver.deleteImportMedia(importId);
    if (!report.fullyDeleted) {
      debugPrint(
        '[AnkiImportCleanupService] ${report.remainingFiles} media file(s) '
        'of $importId stayed locked; the orphan sweep will retry: '
        '${[
          ...report.remainingPaths,
          ...report.remainingDirectories
        ].join(', ')}',
      );
    }
  }
}
