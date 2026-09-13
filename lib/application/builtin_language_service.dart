import 'package:turna/application/course_pack/course_pack.dart';
import 'package:turna/application/course_pack/course_pack_importer.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/lesson_progress_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/data/course_database.dart' show CourseDatabase;
import 'package:turna/data/course_database_seeder.dart' show DatabaseSeeder;
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/language_codes.dart';

/// Uninstall / reinstall lifecycle for packed builtin languages (extracted
/// from [CourseProvider]; behavior locked by multi_language_coexistence_test).
///
/// Both operations mutate the course DB, prefs-backed progress stores and the
/// extracted-media overlay, then hand control back to the provider via the
/// [switchAwayIfActive] / [reloadCourse] callbacks.
class BuiltinLanguageLifecycleService {
  BuiltinLanguageLifecycleService({
    required this.switchAwayIfActive,
    required this.reloadAfterChange,
  });

  /// Move off [languageCode] if it is the active builtin scope (a pack
  /// import is about to rewrite that language).
  final Future<void> Function(String languageCode) switchAwayIfActive;

  /// Re-read the catalog + tree after [languageCode]'s content changed; the
  /// provider decides whether a scope fallback is needed first.
  final Future<void> Function(String languageCode) reloadAfterChange;

  Future<void> uninstall(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    CourseDatabase? db;
    try {
      db = CourseLoader.databaseOrNull();
    } catch (_) {
      db = null;
    }
    if (db == null) return;
    // Collect the language's lesson ids before their rows are deleted — the
    // persisted lesson-progress sets (prefs) must stop counting them.
    Set<String> lessonIds = const {};
    try {
      lessonIds = await CourseRepository(db).lessonIdsForLanguage(code);
    } catch (error) {
      logger.w(
        'BuiltinLanguage: lesson id collection for $code failed: $error',
      );
    }
    await CourseRepository(db).deleteBuiltinLanguage(code);
    // Study logs/daily aggregates live in prefs, not the course DB.
    try {
      if (getIt.isRegistered<StudyLogRepository>()) {
        await getIt<StudyLogRepository>().deleteByLanguage(code);
      }
    } catch (error) {
      logger.w('BuiltinLanguage: study log cleanup for $code failed: $error');
    }
    try {
      if (getIt.isRegistered<LessonProgressProvider>() &&
          lessonIds.isNotEmpty) {
        await getIt<LessonProgressProvider>().removeLessonIds(lessonIds);
      }
    } catch (error) {
      logger.w(
        'BuiltinLanguage: lesson progress cleanup for $code failed: $error',
      );
    }
    LanguageContentStore.drop(code);
    CourseLoader.invalidateCaches();
    // The overlay is normally hydrated when the catalog loaded, but that
    // load fails silently in places — without a re-read here the uninstall
    // would skip (leak) the extracted `imported_courses/<code>/media` tree.
    if (!ImportedLanguageRegistry.instance.contains(code)) {
      try {
        await ImportedLanguageRegistry.instance.hydrate(db);
      } catch (error) {
        logger.w(
          'BuiltinLanguage: overlay re-hydrate for "$code" failed: $error',
        );
      }
    }
    if (ImportedLanguageRegistry.instance.contains(code)) {
      await CoursePackMedia.deleteExtractedMedia(code);
    }
    await reloadAfterChange(code);
  }

  /// Restore a previously uninstalled builtin language: clear the marker and
  /// reseed its content from the packed assets. Learning progress (SRS /
  /// history / mistakes) was deleted at uninstall time and stays gone.
  Future<void> reinstall(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    CourseDatabase? db;
    try {
      db = CourseLoader.databaseOrNull();
    } catch (_) {
      db = null;
    }
    if (db == null) return;
    await CourseRepository(db).clearLanguageUninstallMarker(code);
    await ImportedLanguageRegistry.instance.hydrate(db);
    if (ImportedLanguageRegistry.instance.contains(code)) {
      final packFile = await CoursePackImporter.persistedPackFile(code);
      if (packFile == null || !packFile.existsSync()) {
        throw const CoursePackMissingException();
      }
      await CoursePackImporter(
        db,
        onImportingActiveCode: switchAwayIfActive,
      ).importFromFile(packFile.path);
      await reloadAfterChange(code);
      return;
    }
    final seeded = await DatabaseSeeder(db).seedLanguage(code);
    if (!seeded) {
      logger.w(
        'BuiltinLanguage: reinstall of "$code" seeded nothing '
        '(marker cleared; missing asset?)',
      );
    }
    await reloadAfterChange(code);
  }
}
