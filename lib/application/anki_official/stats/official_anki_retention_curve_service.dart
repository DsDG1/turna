import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:turna/application/memory_curve_provider.dart';

class OfficialAnkiRetentionCurveService {
  const OfficialAnkiRetentionCurveService({this.paths});

  final OfficialAnkiPaths? paths;

  static const List<int> intervalBuckets = [1, 4, 7, 14, 21, 30, 60, 90, 180];

  static int _bucketFor(int intervalDays) {
    for (final b in intervalBuckets) {
      if (intervalDays <= b) return b;
    }
    return intervalBuckets.last;
  }

  Future<List<RetentionPoint>> retentionCurveForCards(List<int> cardIds) async {
    if (cardIds.isEmpty) return const [];
    OfficialAnkiPaths? effectivePaths =
        paths ?? OfficialAnkiCompositionRoot.locatorPaths;
    if (effectivePaths == null) {
      try {
        final support = await getApplicationSupportDirectory();
        effectivePaths = OfficialAnkiPaths.defaultProfile(support);
      } catch (e) {
        debugPrint(
            '[OfficialAnkiRetentionCurveService] supportDir resolution failed: $e');
        return const [];
      }
    }

    final collectionFile = effectivePaths.collectionFile;
    if (!collectionFile.existsSync()) {
      return const [];
    }

    ensureOfficialAnkiSqlite();

    Database? db;
    try {
      db = sqlite3.open(collectionFile.path, mode: OpenMode.readOnly);
      db.execute('PRAGMA busy_timeout = 3000');

      final bucketTotal = <int, int>{};
      final bucketRecalled = <int, int>{};

      const chunkSize = 500;
      for (var i = 0; i < cardIds.length; i += chunkSize) {
        final end =
            (i + chunkSize < cardIds.length) ? i + chunkSize : cardIds.length;
        final chunk = cardIds.sublist(i, end);
        final placeholders = List.filled(chunk.length, '?').join(',');

        final rows = db.select('''
          SELECT lastIvl, ease, COUNT(*) as cnt
          FROM revlog
          WHERE cid IN ($placeholders)
            AND lastIvl > 0
          GROUP BY lastIvl, ease
        ''', chunk);

        for (final row in rows) {
          final lastIvl = row['lastIvl'] as int? ?? 0;
          final ease = row['ease'] as int? ?? 0;
          final count = row['cnt'] as int? ?? 0;
          if (lastIvl <= 0 || count <= 0) continue;

          final b = _bucketFor(lastIvl);
          bucketTotal[b] = (bucketTotal[b] ?? 0) + count;
          if (ease > 1) {
            bucketRecalled[b] = (bucketRecalled[b] ?? 0) + count;
          }
        }
      }

      final curve = <RetentionPoint>[];
      for (final b in intervalBuckets) {
        final total = bucketTotal[b] ?? 0;
        if (total == 0) continue;
        final recalled = bucketRecalled[b] ?? 0;
        curve.add(RetentionPoint(
          intervalBucketDays: b,
          retention: recalled / total,
          sampleSize: total,
        ));
      }
      return curve;
    } catch (e, st) {
      debugPrint(
          '[OfficialAnkiRetentionCurveService] error reading revlog: $e\n$st');
      return const [];
    } finally {
      try {
        db?.dispose();
      } catch (_) {}
    }
  }
}
