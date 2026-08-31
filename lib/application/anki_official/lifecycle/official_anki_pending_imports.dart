import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class OfficialAnkiPendingImportStore {
  const OfficialAnkiPendingImportStore();

  List<OfficialAnkiPendingImport> list(OfficialAnkiDatabase catalog) {
    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final pending = <OfficialAnkiPendingImport>[];
    for (final attempt in attempts.unfinished()) {
      final source = sources.findById(attempt.sourceId);
      if (source == null) continue;
      if (source.state == 'active') continue;
      pending.add(
        OfficialAnkiPendingImport(
          sourceId: source.sourceId,
          attemptId: attempt.attemptId,
          displayName: source.displayName,
          phase: attempt.phase.isNotEmpty ? attempt.phase : attempt.state,
          cardCount: sources.cardCount(source.sourceId),
        ),
      );
    }
    return pending;
  }

  List<OfficialAnkiPendingImport> listForProfile({
    required OfficialAnkiDatabase catalog,
    required String profileId,
  }) {
    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final unfinished = {
      for (final attempt in attempts.unfinished()) attempt.sourceId: attempt,
    };
    final pending = <OfficialAnkiPendingImport>[];
    for (final source in sources.listSources(profileId)) {
      if (source.state == 'active' ||
          source.state == 'retired' ||
          source.state == 'cancelled') {
        continue;
      }
      final attempt = unfinished[source.sourceId];
      pending.add(
        OfficialAnkiPendingImport(
          sourceId: source.sourceId,
          attemptId: attempt?.attemptId ?? source.sourceId,
          displayName: source.displayName,
          phase: attempt?.phase.isNotEmpty == true
              ? attempt!.phase
              : (attempt?.state ?? source.state),
          cardCount: sources.cardCount(source.sourceId),
        ),
      );
    }
    return pending;
  }
}
