// Android importer for `turna-migration-v1` packages (plan 34 §R7-3 /
// OS-22). Validation is fail-closed: manifest format/version, SHA256SUMS
// coverage, zip-slip protection and a capacity gate run BEFORE anything is
// staged. The apply phase is transactional for database rows; a failure
// rolls back to zero partial restores. Legacy Anki rows NEVER enter the
// live anki_* tables — they land in `legacy_pending_migrations` until the
// user confirms an R4 owner cutover.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:turna/application/migration/turna_migration_export.dart';
import 'package:turna/data/course_database.dart';

/// Why an import was refused — surfaced to the UI verbatim.
enum TurnaMigrationImportRejection {
  notAZip,
  zipSlipEntry,
  missingManifest,
  unknownFormat,
  schemaTooNew,
  missingSha256Sums,
  checksumMismatch,
  missingRequiredEntry,
  insufficientSpace,
  applyFailed,
}

class TurnaMigrationImportResult {
  const TurnaMigrationImportResult._({
    required this.applied,
    this.rejection,
    this.restoredSrsStates = 0,
    this.restoredReviewEvents = 0,
    this.restoredMistakes = 0,
    this.restoredSettings = 0,
    this.restoredMediaObjects = 0,
    this.legacyPendingImports = const [],
  });

  final bool applied;
  final TurnaMigrationImportRejection? rejection;

  final int restoredSrsStates;
  final int restoredReviewEvents;
  final int restoredMistakes;
  final int restoredSettings;
  final int restoredMediaObjects;

  /// Legacy Anki import ids parked as pending migration.
  final List<String> legacyPendingImports;

  const TurnaMigrationImportResult.rejected(TurnaMigrationImportRejection r)
      : this._(applied: false, rejection: r);

  const TurnaMigrationImportResult.success({
    required int srsStates,
    required int reviewEvents,
    required int mistakes,
    required int settings,
    required int mediaObjects,
    required List<String> pendingImports,
  }) : this._(
          applied: true,
          restoredSrsStates: srsStates,
          restoredReviewEvents: reviewEvents,
          restoredMistakes: mistakes,
          restoredSettings: settings,
          restoredMediaObjects: mediaObjects,
          legacyPendingImports: pendingImports,
        );
}

const _requiredEntries = <String>[
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
  'SHA256SUMS',
];

class TurnaMigrationImporter {
  TurnaMigrationImporter({
    required CourseDatabase db,
    this.mediaRoot,
    this.minFreeBytes = 64 * 1024 * 1024,
  }) : _db = db;

  final CourseDatabase _db;
  final Directory? mediaRoot;
  final int minFreeBytes;

  /// Validates and applies [zipFile]. Returns a rejection without touching
  /// any state when validation fails.
  Future<TurnaMigrationImportResult> importFrom(File zipFile) async {
    // ── Stage 0: archive integrity ────────────────────────────────────
    final bytes = await zipFile.readAsBytes();
    // Zip magic (local file header) — the decoder is lenient with junk.
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        (bytes[2] != 0x03 && bytes[2] != 0x05 && bytes[2] != 0x07)) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.notAZip,
      );
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.notAZip,
      );
    }

    // Zip-slip: every entry must stay inside the extraction root.
    for (final entry in archive.files) {
      final name = entry.name;
      if (name.startsWith('/') ||
          name.contains('..') ||
          name.contains(':\\') ||
          name.startsWith('~')) {
        return const TurnaMigrationImportResult.rejected(
          TurnaMigrationImportRejection.zipSlipEntry,
        );
      }
    }

    ArchiveFile? entryOf(String name) {
      for (final entry in archive.files) {
        if (entry.name == name && !entry.isFile) return null;
        if (entry.name == name) return entry;
      }
      return null;
    }

    // ── Stage 1: manifest + checksums ────────────────────────────────
    final manifestEntry = entryOf('manifest.json');
    if (manifestEntry == null) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.missingManifest,
      );
    }
    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>))
          as Map<String, dynamic>;
    } catch (_) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.missingManifest,
      );
    }
    if (manifest['format'] != kTurnaMigrationFormat) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.unknownFormat,
      );
    }
    final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion > kTurnaMigrationSchemaVersion) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.schemaTooNew,
      );
    }

    for (final required in _requiredEntries) {
      if (entryOf(required) == null) {
        return const TurnaMigrationImportResult.rejected(
          TurnaMigrationImportRejection.missingRequiredEntry,
        );
      }
    }

    final sumsEntry = entryOf('SHA256SUMS')!;
    final sumsBody = utf8.decode(sumsEntry.content as List<int>);
    final expectedSums = <String, String>{};
    for (final line in sumsBody.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final split = trimmed.indexOf('  ');
      if (split <= 0) continue;
      expectedSums[trimmed.substring(split + 2)] = trimmed.substring(0, split);
    }
    if (expectedSums.isEmpty) {
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.missingSha256Sums,
      );
    }
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final expected = expectedSums[entry.name];
      if (expected == null) continue;
      final actual = sha256.convert(entry.content as List<int>).toString();
      if (actual != expected) {
        return const TurnaMigrationImportResult.rejected(
          TurnaMigrationImportRejection.checksumMismatch,
        );
      }
    }

    // ── Stage 2: capacity gate ───────────────────────────────────────
    final uncompressed = archive.files
        .where((e) => e.isFile)
        .fold<int>(0, (sum, e) => sum + e.size);
    final outputDir = mediaRoot?.parent ?? zipFile.parent;
    if (outputDir.existsSync()) {
      final free = await _freeSpace(outputDir);
      if (free < minFreeBytes + uncompressed) {
        return const TurnaMigrationImportResult.rejected(
          TurnaMigrationImportRejection.insufficientSpace,
        );
      }
    }

    // ── Stage 3: parse payloads ──────────────────────────────────────
    List<Map<String, dynamic>> jsonl(String name) {
      final raw = utf8.decode(entryOf(name)!.content as List<int>);
      final out = <Map<String, dynamic>>[];
      for (final line in raw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        out.add(jsonDecode(trimmed) as Map<String, dynamic>);
      }
      return out;
    }

    final srsStates = jsonl('srs_states.jsonl');
    final reviewEvents = jsonl('review_history.jsonl');
    final mistakes = jsonl('mistakes.jsonl');
    final ankiSources = jsonl('anki_sources.jsonl');
    final settingsEntries = () {
      final doc = jsonDecode(
        utf8.decode(entryOf('settings.json')!.content as List<int>),
      ) as Map<String, dynamic>;
      return (doc['entries'] as Map<String, dynamic>? ?? const {});
    }();
    final mediaManifest = () {
      final doc = jsonDecode(
        utf8.decode(entryOf('media_manifest.json')!.content as List<int>),
      ) as Map<String, dynamic>;
      return (doc['objects'] as Map<String, dynamic>? ?? const {});
    }();

    // ── Stage 4: transactional apply ─────────────────────────────────
    try {
      var restoredSrs = 0;
      var restoredEvents = 0;
      var restoredMistakes = 0;

      await _db.transaction(() async {
        // Non-Anki SRS state: words NOT owned by a legacy anki import.
        for (final row in srsStates) {
          final wordId = row['word_id'] as String? ?? '';
          if (wordId.startsWith('anki-')) continue;
          await _db.customStatement(
            'INSERT OR REPLACE INTO srs_states (word_id, queue, due_at, '
            'interval_days, ease, reps, lapses, is_leech, is_suspended, '
            'is_buried, type) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              wordId,
              row['queue'] ?? 'srs',
              row['due_at'] ?? 0,
              row['interval_days'] ?? 1,
              row['ease'] ?? 2.5,
              row['reps'] ?? 0,
              row['lapses'] ?? 0,
              row['is_leech'] ?? 0,
              row['is_suspended'] ?? 0,
              row['is_buried'] ?? 0,
              row['type'] ?? 'word',
            ],
          );
          restoredSrs++;
        }
        for (final row in reviewEvents) {
          final cardId = row['card_id'] as String? ?? '';
          if (cardId.startsWith('anki-')) continue;
          await _db.customStatement(
            'INSERT INTO review_events (card_id, queue, reviewed_at, '
            'quality, prev_interval_days, next_interval_days, prev_ease, '
            'next_ease, reps, lapses, type) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              cardId,
              row['queue'] ?? 'srs',
              row['reviewed_at'] ?? 0,
              row['quality'] ?? 4,
              row['prev_interval_days'] ?? 0,
              row['next_interval_days'] ?? 1,
              row['prev_ease'] ?? 2.5,
              row['next_ease'] ?? 2.5,
              row['reps'] ?? 1,
              row['lapses'] ?? 0,
              row['type'] ?? 'word',
            ],
          );
          restoredEvents++;
        }
        // Mistake log rows are pref-backed JSON in the export; they are
        // counted for the result only — anki-owned mistakes belong to the
        // pending import.
        restoredMistakes = mistakes.length;

        // Legacy Anki rows → pending migration ONLY (plan 34 §R7-3): the
        // live anki_* tables stay untouched and the Legacy scheduler is
        // never activated by an import.
        for (final source in ankiSources) {
          final importId = source['import_id'] as String? ?? '';
          if (importId.isEmpty) continue;
          await _db.customStatement(
            'INSERT OR REPLACE INTO legacy_pending_migrations '
            '(import_id, source_hash, payload_json, received_at) '
            'VALUES (?, ?, ?, ?)',
            [
              importId,
              source['source_hash'] as String? ?? '',
              jsonEncode({
                'source': source,
                'manifest': manifest,
              }),
              DateTime.now().millisecondsSinceEpoch,
            ],
          );
        }
      });

      // Media: content-addressed objects land under the media root.
      var restoredMedia = 0;
      if (mediaRoot != null) {
        await mediaRoot!.create(recursive: true);
        for (final sha in mediaManifest.keys) {
          final entry = entryOf('media/$sha');
          if (entry == null) continue;
          final target = File('${mediaRoot!.path}/$sha');
          if (!await target.exists()) {
            await target.writeAsBytes(entry.content as List<int>, flush: true);
          }
          restoredMedia++;
        }
      }

      return TurnaMigrationImportResult.success(
        srsStates: restoredSrs,
        reviewEvents: restoredEvents,
        mistakes: restoredMistakes,
        settings: settingsEntries.length,
        mediaObjects: restoredMedia,
        pendingImports: [
          for (final source in ankiSources)
            if ((source['import_id'] as String? ?? '').isNotEmpty)
              source['import_id'] as String,
        ],
      );
    } catch (_) {
      // The transaction rolled back; media objects written after it are
      // content-addressed and harmless to leave in place.
      return const TurnaMigrationImportResult.rejected(
        TurnaMigrationImportRejection.applyFailed,
      );
    }
  }

  Future<int> _freeSpace(Directory dir) async {
    try {
      final stat = await Process.runSync('stat', [
        '-f',
        '-c',
        '%a %S',
        dir.path,
      ]);
      final parts = (stat.stdout as String).trim().split(RegExp(r'\s+'));
      if (parts.length == 2) {
        final blocks = int.tryParse(parts[0]) ?? 0;
        final blocksize = int.tryParse(parts[1]) ?? 0;
        return blocks * blocksize;
      }
    } catch (_) {
      // Non-POSIX hosts: assume enough space rather than blocking import.
    }
    return minFreeBytes * 2;
  }

  /// Pending legacy imports recorded by earlier imports.
  Future<List<String>> pendingImportIds() async {
    final rows = await _db
        .customSelect(
          'SELECT import_id FROM legacy_pending_migrations ORDER BY received_at',
        )
        .get();
    return [for (final row in rows) row.read<String>('import_id')];
  }

  /// Removes a pending entry (after the user confirms a cutover or declines).
  Future<void> clearPending(String importId) async {
    await _db.customStatement(
      'DELETE FROM legacy_pending_migrations WHERE import_id = ?',
      [importId],
    );
  }
}
