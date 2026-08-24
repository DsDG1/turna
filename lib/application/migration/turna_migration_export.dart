// Platform-neutral `turna-migration-v1` logical export (doc 34 §5.4).
//
// Used as the OHOS product EOL data-exit path and as a reusable dump of
// CourseDatabase + related prefs into a zip that Android can stage/validate
// without copying OS-specific RDB/SQLite files. Source device data is never
// mutated. Secrets / API keys are excluded via [BackupManifestPolicy].

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:turna/application/backup/backup_manifest_policy.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/service/locator.dart';

/// Logical package format id written into [manifest.json].
const String kTurnaMigrationFormat = 'turna-migration-v1';

/// Schema version stamped onto each table/object blob in the package.
const int kTurnaMigrationSchemaVersion = 1;

class TurnaMigrationExportResult {
  const TurnaMigrationExportResult({
    required this.zipFile,
    required this.stagingDir,
    required this.sha256Sums,
    required this.manifest,
  });

  final File zipFile;
  final Directory stagingDir;
  final Map<String, String> sha256Sums;
  final Map<String, dynamic> manifest;
}

/// Builds a `turna-migration-v1.zip` from [db] + SharedPreferences.
///
/// Optional [legacyMediaRoot] (typically `…/anki_media`) is content-addressed
/// into `media/<sha256>` with paths recorded in `media_manifest.json`.
/// Optional [prefs] / [appVersion] / [buildNumber] / [platform] override
/// production lookups for tests.
class TurnaMigrationExporter {
  TurnaMigrationExporter({
    required CourseDatabase db,
    Directory? legacyMediaRoot,
    SharedPreferences? prefs,
    String appVersion = '0.0.0-test',
    String buildNumber = '0',
    String platform = 'unknown',
    AppPrefs? appPrefs,
  })  : _db = db,
        _legacyMediaRoot = legacyMediaRoot,
        _prefsOverride = prefs,
        _appVersion = appVersion,
        _buildNumber = buildNumber,
        _platform = platform,
        _appPrefs = appPrefs;

  final CourseDatabase _db;
  final Directory? _legacyMediaRoot;
  final SharedPreferences? _prefsOverride;
  final String _appVersion;
  final String _buildNumber;
  final String _platform;
  final AppPrefs? _appPrefs;

  /// Writes the package under [outputDir] (created if needed) and returns the
  /// zip plus staging directory. Does not modify [db] or prefs.
  Future<TurnaMigrationExportResult> exportTo(Directory outputDir) async {
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    final staging = Directory(
      p.join(
        outputDir.path,
        'staging-${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await staging.create(recursive: true);
    final mediaDir = Directory(p.join(staging.path, 'media'));
    await mediaDir.create(recursive: true);

    final settings = await _collectSettings();
    final profile = _collectProfile(settings);
    final courseProgress = _courseProgressLines(settings);
    final mistakes = _mistakeLines(settings);

    final srsStates = await _selectJsonl(
      'SELECT * FROM srs_states ORDER BY word_id',
    );
    final reviewHistory = await _selectJsonl(
      'SELECT * FROM review_events ORDER BY id',
    );
    final ankiSources = await _selectJsonl(
      'SELECT * FROM anki_imports ORDER BY import_id',
    );
    final ankiNotes = await _selectJsonl(
      'SELECT * FROM anki_notes ORDER BY import_id, note_id',
    );
    final ankiCards = await _selectJsonl(
      'SELECT * FROM anki_cards_meta ORDER BY import_id, card_id',
    );
    final introductions = await _safeSelectJsonl(
      'SELECT * FROM anki_card_introduction_states '
      'ORDER BY course_id, source_id, card_id',
    );

    final mediaManifest = <String, dynamic>{};
    if (_legacyMediaRoot != null && await _legacyMediaRoot!.exists()) {
      await _copyMediaContentAddressed(_legacyMediaRoot!, mediaDir, mediaManifest);
    }

    final createdAt = DateTime.now().toUtc().toIso8601String();
    final manifest = <String, dynamic>{
      'format': kTurnaMigrationFormat,
      'schemaVersion': kTurnaMigrationSchemaVersion,
      'createdAtUtc': createdAt,
      'appVersion': _appVersion,
      'buildNumber': _buildNumber,
      'platform': _platform,
      'driftSchema': _db.schemaVersion,
      'counts': <String, int>{
        'courseProgress': courseProgress.length,
        'srsStates': srsStates.length,
        'reviewHistory': reviewHistory.length,
        'mistakes': mistakes.length,
        'ankiSources': ankiSources.length,
        'ankiNotes': ankiNotes.length,
        'ankiCards': ankiCards.length,
        'introductions': introductions.length,
        'mediaObjects': mediaManifest.length,
      },
      // Legacy Anki payloads must land as pending migration on Android.
      'legacyAnkiDisposition': 'legacyPendingMigration',
    };

    await _writeJson(staging, 'manifest.json', manifest);
    await _writeJson(staging, 'profile.json', {
      'schemaVersion': kTurnaMigrationSchemaVersion,
      ...profile,
    });
    await _writeJson(staging, 'settings.json', {
      'schemaVersion': kTurnaMigrationSchemaVersion,
      'entries': settings,
    });
    await _writeJsonl(staging, 'course_progress.jsonl', courseProgress);
    await _writeJsonl(staging, 'srs_states.jsonl', srsStates);
    await _writeJsonl(staging, 'review_history.jsonl', reviewHistory);
    await _writeJsonl(staging, 'mistakes.jsonl', mistakes);
    await _writeJsonl(staging, 'anki_sources.jsonl', ankiSources);
    await _writeJsonl(staging, 'anki_notes.jsonl', ankiNotes);
    await _writeJsonl(staging, 'anki_cards.jsonl', ankiCards);
    await _writeJsonl(staging, 'introductions.jsonl', introductions);
    await _writeJson(staging, 'media_manifest.json', {
      'schemaVersion': kTurnaMigrationSchemaVersion,
      'objects': mediaManifest,
    });

    final namedEntries = <String>[
      'manifest.json',
      'profile.json',
      'settings.json',
      'course_progress.jsonl',
      'srs_states.jsonl',
      'review_history.jsonl',
      'mistakes.jsonl',
      'anki_sources.jsonl',
      'anki_notes.jsonl',
      'anki_cards.jsonl',
      'introductions.jsonl',
      'media_manifest.json',
    ];
    final sha256Sums = <String, String>{};
    for (final name in namedEntries) {
      sha256Sums[name] = await _hashFile(File(p.join(staging.path, name)));
    }
    for (final entry in mediaManifest.entries) {
      final sha = entry.key;
      final mediaPath = 'media/$sha';
      sha256Sums[mediaPath] =
          await _hashFile(File(p.join(staging.path, mediaPath)));
    }
    final sumsBody = StringBuffer();
    for (final e in sha256Sums.entries) {
      sumsBody.writeln('${e.value}  ${e.key}');
    }
    await File(p.join(staging.path, 'SHA256SUMS'))
        .writeAsString(sumsBody.toString(), flush: true);

    final zipFile = File(
      p.join(outputDir.path, 'turna-migration-v1.zip'),
    );
    await _packZip(staging, namedEntries, mediaManifest.keys.toList(), zipFile);

    return TurnaMigrationExportResult(
      zipFile: zipFile,
      stagingDir: staging,
      sha256Sums: sha256Sums,
      manifest: manifest,
    );
  }

  Future<Map<String, Object?>> _collectSettings() async {
    final out = <String, Object?>{};
    if (_prefsOverride != null) {
      for (final key in _prefsOverride!.getKeys()) {
        final sanitized = BackupManifestPolicy.sanitizeForSerialization(
          key,
          _prefsOverride!.get(key),
        );
        if (sanitized != null) out[key] = sanitized;
      }
      return out;
    }
    if (_appPrefs != null) {
      final prefs = _appPrefs!.preferences;
      final keys = prefs.getKeys().getValue();
      for (final key in keys) {
        final entry = BackupManifestPolicy.entryFor(key);
        if (entry == null) continue;
        final Object? value;
        switch (entry.primaryType) {
          case BackupPrefType.bool_:
            value = prefs.getBool(key, defaultValue: false).getValue();
          case BackupPrefType.int_:
            value = prefs.getInt(key, defaultValue: 0).getValue();
          case BackupPrefType.double_:
            value = prefs.getDouble(key, defaultValue: 0.0).getValue();
          case BackupPrefType.string:
            value = prefs.getString(key, defaultValue: '').getValue();
          case BackupPrefType.stringList:
            value =
                prefs.getStringList(key, defaultValue: const []).getValue();
        }
        final sanitized =
            BackupManifestPolicy.sanitizeForSerialization(key, value);
        if (sanitized != null) out[key] = sanitized;
      }
      return out;
    }
    final sp = await SharedPreferences.getInstance();
    for (final key in sp.getKeys()) {
      final sanitized = BackupManifestPolicy.sanitizeForSerialization(
        key,
        sp.get(key),
      );
      if (sanitized != null) out[key] = sanitized;
    }
    return out;
  }

  Map<String, dynamic> _collectProfile(Map<String, Object?> settings) {
    return <String, dynamic>{
      'language': settings[PrefsConstants.currentLanguage] ?? 'turkish',
      'score': settings[LocalStateKeys.score] ?? 0,
      'streak': settings[LocalStateKeys.streak] ?? 0,
      'gems': settings[LocalStateKeys.gems] ?? 0,
      'lessonsCompleted': settings[LocalStateKeys.lessonsCompleted] ?? 0,
      'wordsLearned': settings[LocalStateKeys.wordsLearned] ?? 0,
    };
  }

  List<Map<String, dynamic>> _courseProgressLines(
    Map<String, Object?> settings,
  ) {
    final lines = <Map<String, dynamic>>[];
    void addList(String key) {
      final raw = settings[key];
      if (raw is List) {
        for (final id in raw.whereType<String>()) {
          lines.add({
            'schemaVersion': kTurnaMigrationSchemaVersion,
            'kind': key,
            'id': id,
          });
        }
      }
    }

    addList(LocalStateKeys.completedLessonIds);
    addList(LocalStateKeys.perfectLessonIds);
    return lines;
  }

  List<Map<String, dynamic>> _mistakeLines(Map<String, Object?> settings) {
    final raw = settings[LocalStateKeys.mistakeLog];
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            {
              'schemaVersion': kTurnaMigrationSchemaVersion,
              ...Map<String, dynamic>.from(item),
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _selectJsonl(String sql) async {
    final rows = await _db.customSelect(sql).get();
    return [
      for (final row in rows)
        {
          'schemaVersion': kTurnaMigrationSchemaVersion,
          ..._normalizeRow(row.data),
        },
    ];
  }

  /// Introduction table is created in a late migration; empty on fresh DBs.
  Future<List<Map<String, dynamic>>> _safeSelectJsonl(String sql) async {
    try {
      return await _selectJsonl(sql);
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _normalizeRow(Map<String, Object?> data) {
    final out = <String, dynamic>{};
    for (final e in data.entries) {
      final v = e.value;
      if (v is DateTime) {
        out[e.key] = v.toUtc().toIso8601String();
      } else if (v is Uint8List) {
        out[e.key] = base64Encode(v);
      } else {
        out[e.key] = v;
      }
    }
    return out;
  }

  Future<void> _copyMediaContentAddressed(
    Directory root,
    Directory mediaDir,
    Map<String, dynamic> manifest,
  ) async {
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final sha = await _hashFile(file);
      final dest = File(p.join(mediaDir.path, sha));
      if (!await dest.exists()) {
        await file.copy(dest.path);
      }
      final relative =
          p.relative(file.path, from: root.path).replaceAll('\\', '/');
      manifest[sha] = <String, dynamic>{
        'schemaVersion': kTurnaMigrationSchemaVersion,
        'bytes': await file.length(),
        'logicalPath': relative,
      };
    }
  }

  Future<void> _writeJson(
    Directory dir,
    String name,
    Map<String, dynamic> json,
  ) async {
    await File(p.join(dir.path, name)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
  }

  Future<void> _writeJsonl(
    Directory dir,
    String name,
    List<Map<String, dynamic>> rows,
  ) async {
    final sink = File(p.join(dir.path, name)).openWrite();
    try {
      for (final row in rows) {
        sink.writeln(jsonEncode(row));
      }
    } finally {
      await sink.close();
    }
  }

  Future<String> _hashFile(File file) async {
    const chunkSize = 1024 * 1024;
    final digestSink = _DigestSink();
    final sink = sha256.startChunkedConversion(digestSink);
    final raf = await file.open();
    try {
      final buffer = Uint8List(chunkSize);
      while (true) {
        final read = await raf.readInto(buffer);
        if (read <= 0) break;
        sink.add(Uint8List.sublistView(buffer, 0, read));
      }
    } finally {
      await raf.close();
    }
    sink.close();
    return digestSink.value.toString();
  }

  Future<void> _packZip(
    Directory staging,
    List<String> namedEntries,
    List<String> mediaShas,
    File target,
  ) async {
    final archive = Archive();
    for (final name in namedEntries) {
      final bytes = await File(p.join(staging.path, name)).readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    for (final sha in mediaShas) {
      final name = 'media/$sha';
      final bytes = await File(p.join(staging.path, name)).readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    final sums = await File(p.join(staging.path, 'SHA256SUMS')).readAsBytes();
    archive.addFile(ArchiveFile('SHA256SUMS', sums.length, sums));
    final encoded = ZipEncoder().encode(archive);
    await target.writeAsBytes(encoded, flush: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
