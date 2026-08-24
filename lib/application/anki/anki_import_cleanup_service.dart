// Project imports:
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
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

  const AnkiImportCleanupService({
    required this.repository,
    required this.srsProvider,
    required this.importDao,
    required this.noteDao,
    this.reviewHistoryDao,
    required this.audioResolver,
    this.unificationDao,
    this.mistakeProvider,
  });

  Future<void> deleteAll(String importId) async {
    await repository.deleteByTag('anki:$importId');
    final sections = await repository.sectionShells();
    for (final section in sections) {
      if (section.id.startsWith('anki-$importId-')) {
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
    await audioResolver.deleteImportMedia(importId);
    await importDao.delete(importId);
    await mistakeProvider?.removeForAnkiDeletion(idPrefixes: [prefix]);
    // Defense in depth: the dedup authority is the persisted inventory, but
    // the orchestrator's in-process caches (placements, presentations, SRS
    // ids, in-flight keys) must also be retired so a same-process re-import
    // of this package is never mistaken for "already imported".
    UnifiedAnkiImportOrchestrator.instance.invalidate(importId: importId);
  }
}
