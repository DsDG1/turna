// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:package_info_plus/package_info_plus.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/service/locator.dart';

/// Encoded progress / settings keys carried in an export and written back on
/// import. Each entry pairs a prefs key with its scalar type so the export can
/// read the raw value and the import can dispatch to the matching setter.
enum _PrefType { bool_, int_, double_, string, stringList }

class _PrefEntry {
  final String key;
  final _PrefType type;
  const _PrefEntry(this.key, this.type);
}

/// All progress + settings keys bundled into a "progress" export. Kept as a
/// single list so read and write stay in lockstep — add a key here and it
/// round-trips automatically. Course-content keys are handled separately by
/// [ExportService._readCourse].
const List<_PrefEntry> _progressManifest = [
  // Marker / game state
  _PrefEntry(LocalStateKeys.initialized, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.score, _PrefType.int_),
  _PrefEntry(LocalStateKeys.streak, _PrefType.int_),
  _PrefEntry(LocalStateKeys.lastStreakDate, _PrefType.string),
  _PrefEntry(LocalStateKeys.lessonsCompleted, _PrefType.int_),
  _PrefEntry(LocalStateKeys.perfectLessons, _PrefType.int_),
  _PrefEntry(LocalStateKeys.streakWasBroken, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.wordsLearned, _PrefType.int_),
  // Per-lesson progress
  _PrefEntry(LocalStateKeys.completedLessonIds, _PrefType.stringList),
  _PrefEntry(LocalStateKeys.perfectLessonIds, _PrefType.stringList),
  // Currency / achievements
  _PrefEntry(LocalStateKeys.gems, _PrefType.int_),
  _PrefEntry(LocalStateKeys.achievements, _PrefType.stringList),
  // SRS / mistakes
  _PrefEntry(LocalStateKeys.srsState, _PrefType.string),
  _PrefEntry(LocalStateKeys.lessonWordLinks, _PrefType.string),
  _PrefEntry(LocalStateKeys.grammarReviewState, _PrefType.string),
  _PrefEntry(LocalStateKeys.mistakeLog, _PrefType.string),
  // Study logs / daily stats (JSON-string keys — see study_log_repository.dart)
  _PrefEntry('study.logs', _PrefType.string),
  _PrefEntry('study.logs.recent', _PrefType.string),
  _PrefEntry('study.dailyStats', _PrefType.string),
  // Settings (so a restore also brings the learner's config)
  _PrefEntry(LocalStateKeys.themeMode, _PrefType.string),
  _PrefEntry(LocalStateKeys.soundEffects, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.haptic, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.ttsSpeed, _PrefType.double_),
  _PrefEntry(LocalStateKeys.ttsEngine, _PrefType.string),
  _PrefEntry(LocalStateKeys.ttsAvailabilityPromptShown, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.dailyReminderEnabled, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.dailyReminderHour, _PrefType.int_),
  _PrefEntry(LocalStateKeys.dailyReminderMinute, _PrefType.int_),
  _PrefEntry(LocalStateKeys.useXiaoyiHint, _PrefType.bool_),
  _PrefEntry(LocalStateKeys.contentVersionAcknowledged, _PrefType.string),
  // Account + language
  _PrefEntry(PrefsConstants.currentLanguage, _PrefType.string),
  _PrefEntry(PrefsConstants.authUser, _PrefType.string), // JSON string
];

class ImportResult {
  final bool progressRestored;
  final bool hasCoursePayload;

  const ImportResult({
    required this.progressRestored,
    required this.hasCoursePayload,
  });
}

/// Builds / restores a single JSON export file containing optional `progress`
/// (prefs snapshot) and `course` (bundled course assets) sections.
///
/// Exported file shape:
/// ```
/// { "meta": { app, version, buildNumber, language, exportedAt, schema, contents },
///   "progress"?: { <prefsKey>: <value>, ... },   // scalar values only
///   "course"?:    { "<assetPath>": "<file content>", ... } }
/// ```
class ExportService {
  ExportService(this._prefs);

  final AppPrefs _prefs;

  Future<File> export({
    required bool includeProgress,
    required bool includeCourse,
  }) async {
    assert(includeProgress || includeCourse, 'Nothing selected to export');

    final info = await PackageInfo.fromPlatform();
    final meta = <String, dynamic>{
      'app': info.packageName,
      'version': info.version,
      'buildNumber': info.buildNumber,
      'language': _prefs.currentLanguage.getValue(),
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'schema': 1,
      'contents': {
        'progress': includeProgress,
        'course': includeCourse,
      },
    };

    final payload = <String, dynamic>{'meta': meta};
    if (includeProgress) payload['progress'] = _readProgress();
    if (includeCourse) payload['course'] = await _readCourse();

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/turna_export_$ts.json');
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  Future<void> share(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Turna export',
    );
  }

  /// Parses an export file and writes its progress section back to prefs.
  /// Course content is returned (not applied to the DB) — see [ImportResult].
  Future<ImportResult> importFromFile(String path) async {
    final raw = await File(path).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Export file is not a JSON object');
    }
    final meta = decoded['meta'];
    if (meta is! Map<String, dynamic> || meta['app'] == null) {
      throw const FormatException('Missing or invalid export metadata');
    }

    bool progressRestored = false;
    final progress = decoded['progress'];
    if (progress is Map<String, dynamic>) {
      await _writeProgress(progress);
      progressRestored = true;
    }

    final hasCourse = decoded['course'] is Map<String, dynamic>;
    return ImportResult(
      progressRestored: progressRestored,
      hasCoursePayload: hasCourse,
    );
  }

  Map<String, dynamic> _readProgress() {
    final out = <String, dynamic>{};
    final prefs = _prefs.preferences;
    // Only export keys that actually exist in the store — the streaming_shared_
    // preferences getters require a non-null default and cannot distinguish a
    // missing key from a default value, so we filter by the live key set.
    final keys = prefs.getKeys().getValue();
    for (final entry in _progressManifest) {
      if (!keys.contains(entry.key)) continue;
      switch (entry.type) {
        case _PrefType.bool_:
          out[entry.key] =
              prefs.getBool(entry.key, defaultValue: false).getValue();
        case _PrefType.int_:
          out[entry.key] = prefs.getInt(entry.key, defaultValue: 0).getValue();
        case _PrefType.double_:
          out[entry.key] =
              prefs.getDouble(entry.key, defaultValue: 0.0).getValue();
        case _PrefType.string:
          out[entry.key] =
              prefs.getString(entry.key, defaultValue: '').getValue();
        case _PrefType.stringList:
          out[entry.key] =
              prefs.getStringList(entry.key, defaultValue: const []).getValue();
      }
    }
    return out;
  }

  Future<void> _writeProgress(Map<String, dynamic> data) async {
    for (final entry in _progressManifest) {
      if (!data.containsKey(entry.key)) continue;
      final value = data[entry.key];
      switch (entry.type) {
        case _PrefType.bool_:
          if (value is bool) await _prefs.setBool(entry.key, value: value);
        case _PrefType.int_:
          if (value is int) await _prefs.setInt(entry.key, value);
        case _PrefType.double_:
          if (value is num) await _prefs.setDouble(entry.key, value.toDouble());
        case _PrefType.string:
          if (value is String) await _prefs.setString(entry.key, value);
        case _PrefType.stringList:
          if (value is List) {
            await _prefs.setStringList(
              entry.key,
              value.map((e) => e.toString()).toList(),
            );
          }
      }
    }
  }

  /// Reads the bundled course JSON assets into a `Map<assetPath, fileContent>`.
  /// The asset files are the source of truth (the Drift DB is a derived cache),
  /// so re-reading them is simpler and lossless compared to dumping the DB.
  Future<Map<String, String>> _readCourse() async {
    // Must be a mutable map — `const {}` is unmodifiable and throws when
    // assets are assigned (export with "course content" checked).
    final out = <String, String>{};
    const baseDir = CourseLoader.baseDir;

    // Top-level files.
    for (final asset in [
      CourseLoader.indexAsset,
      CourseLoader.vocabAsset,
      CourseLoader.grammarPointsAsset,
      CourseLoader.expressionsAsset,
    ]) {
      out[asset] = await rootBundle.loadString(asset);
    }

    // Per-section files listed in index.json (`file` is relative to baseDir).
    final indexRaw = await rootBundle.loadString(CourseLoader.indexAsset);
    final index = jsonDecode(indexRaw) as Map<String, dynamic>;
    final sections = index['sections'];
    if (sections is List) {
      for (final section in sections) {
        if (section is! Map) continue;
        final file = section['file'];
        if (file is! String || file.isEmpty) continue;
        final assetPath = '$baseDir/$file';
        out[assetPath] = await rootBundle.loadString(assetPath);
      }
    }
    return out;
  }
}
