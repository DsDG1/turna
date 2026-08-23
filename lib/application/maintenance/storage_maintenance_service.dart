import 'package:path/path.dart' as p;

import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/core/log_capture.dart';
import 'storage_maintenance_platform_stub.dart'
    if (dart.library.io) 'storage_maintenance_platform_io.dart' as platform;

class StorageMaintenanceSnapshot {
  const StorageMaintenanceSnapshot({
    required this.databaseBytes,
    required this.ankiMediaBytes,
    required this.decryptCacheBytes,
    required this.aiCacheEntries,
    required this.logBytes,
  });

  final int databaseBytes;
  final int ankiMediaBytes;
  final int decryptCacheBytes;
  final int aiCacheEntries;
  final int logBytes;
}

class StorageMaintenanceService {
  Future<StorageMaintenanceSnapshot> inspect() async {
    final db = getIt<CourseDatabase>();
    final pageCount = await db.customSelect('PRAGMA page_count').getSingle();
    final pageSize = await db.customSelect('PRAGMA page_size').getSingle();
    final pageCountValue = pageCount.data.values.first as int;
    final pageSizeValue = pageSize.data.values.first as int;
    final databaseBytes = pageCountValue * pageSizeValue;
    final base = await AnkiAudioResolver().getMediaBasePath();
    final decrypt = await getIt<AnkiNoteDao>().prerenderCacheStats();
    final aiEntries = getIt.isRegistered<AiEngine>()
        ? getIt<AiEngine>().cacheStats().entries
        : 0;
    return StorageMaintenanceSnapshot(
      databaseBytes: databaseBytes,
      ankiMediaBytes:
          await platform.directorySizeBytes(p.join(base, 'anki_media')),
      decryptCacheBytes: decrypt.byteCount,
      aiCacheEntries: aiEntries,
      logBytes: await platform.fileSizeBytes(
        LogCapture.instance.fileForDisplay?.path,
      ),
    );
  }

  Future<void> clearRegenerableCaches() async {
    await getIt<AnkiNoteDao>().deletePrerenderedByPrefix('anki-');
  }

  Future<String> checkDatabaseIntegrity() async {
    final rows = await getIt<CourseDatabase>()
        .customSelect('PRAGMA integrity_check')
        .get();
    return rows.map((row) => row.data.values.join(' ')).join('\n');
  }

  Future<void> rebuildIndexes() async {
    final db = getIt<CourseDatabase>();
    await db.customStatement('REINDEX');
    await db.customStatement('PRAGMA optimize');
  }
}
