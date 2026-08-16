import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// One profile, one Collection owner. Implementations must serialize writes.
abstract class OfficialAnkiEngine {
  Future<OfficialAnkiEngineInfo> engineInfo();

  Future<void> openProfile(OfficialAnkiPaths paths);

  Future<void> closeCollection();

  Future<void> checkCollection();

  Future<String> createBackup();

  Future<void> restoreBackup(String backupId);

  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  });

  Future<OfficialAnkiProgress> latestProgress();

  Future<void> cancel();

  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  });

  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds);

  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  );

  Future<void> dispose();
}
