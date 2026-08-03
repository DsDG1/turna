// Project imports:
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';

/// Removes every persisted resource belonging to one Anki import.
///
/// Keeping this operation in one place prevents force-replace/uninstall paths
/// from leaving SRS rows, review history, NoteStore snapshots, media, or
/// decrypted HTML behind.
class AnkiImportCleanupService {
  final CourseRepository repository;
  final SrsProvider srsProvider;
  final AnkiImportDao importDao;
  final AnkiNoteDao noteDao;
  final ReviewHistoryDao reviewHistoryDao;
  final AnkiAudioResolver audioResolver;

  const AnkiImportCleanupService({
    required this.repository,
    required this.srsProvider,
    required this.importDao,
    required this.noteDao,
    required this.reviewHistoryDao,
    required this.audioResolver,
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
    await reviewHistoryDao.deleteByCardPrefix(prefix);
    await noteDao.deleteByImport(importId);
    await noteDao.deletePrerenderedByPrefix(prefix);
    await audioResolver.deleteImportMedia(importId);
    await importDao.delete(importId);
  }
}
