import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/stats/official_anki_retention_curve_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfficialAnkiRetentionCurveService', () {
    late Directory tempDir;
    late File collectionFile;
    late Database db;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('anki_curve_test');
      final root = Directory('${tempDir.path}/official_anki/default')
        ..createSync(recursive: true);
      collectionFile = File('${root.path}/collection.anki2');
      db = sqlite3.open(collectionFile.path);
      db.execute('''
        CREATE TABLE revlog (
          id INTEGER PRIMARY KEY,
          cid INTEGER NOT NULL,
          usn INTEGER NOT NULL,
          ease INTEGER NOT NULL,
          ivl INTEGER NOT NULL,
          lastIvl INTEGER NOT NULL,
          factor INTEGER NOT NULL,
          time INTEGER NOT NULL,
          type INTEGER NOT NULL
        );
      ''');
    });

    tearDown(() {
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('returns empty when cardIds is empty', () async {
      final paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot: collectionFile.parent,
      );
      final service = OfficialAnkiRetentionCurveService(paths: paths);
      final points = await service.retentionCurveForCards([]);
      expect(points, isEmpty);
    });

    test('calculates correct retention per interval bucket from revlog',
        () async {
      // Insert sample revlogs:
      // cid 100: lastIvl=1 (bucket 1), ease=3 (recalled)
      // cid 100: lastIvl=1 (bucket 1), ease=1 (failed)
      // cid 200: lastIvl=7 (bucket 7), ease=3 (recalled)
      // cid 200: lastIvl=7 (bucket 7), ease=2 (recalled)
      db.execute('''
        INSERT INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type) VALUES
        (1001, 100, -1, 3, 3, 1, 2500, 5000, 1),
        (1002, 100, -1, 1, 1, 1, 2500, 4000, 1),
        (1003, 200, -1, 3, 15, 7, 2500, 6000, 1),
        (1004, 200, -1, 2, 10, 7, 2500, 5500, 1);
      ''');

      final paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot: collectionFile.parent,
      );
      final service = OfficialAnkiRetentionCurveService(paths: paths);
      final points = await service.retentionCurveForCards([100, 200]);

      expect(points.length, 2);

      final bucket1 = points.firstWhere((p) => p.intervalBucketDays == 1);
      expect(bucket1.sampleSize, 2);
      expect(bucket1.retention, 0.5); // 1 recalled / 2 total

      final bucket7 = points.firstWhere((p) => p.intervalBucketDays == 7);
      expect(bucket7.sampleSize, 2);
      expect(bucket7.retention, 1.0); // 2 recalled / 2 total
    });
  });

  group('OfficialReviewSession subdeck prioritization', () {
    test('orderDecksForReview prioritizes parent decks with lower level', () {
      final decks = [
        const OfficialAnkiDeckNode(
          deckId: 2,
          name: 'Vocab::Chapter1',
          level: 1,
          reviewCount: 10,
        ),
        const OfficialAnkiDeckNode(
          deckId: 1,
          name: 'Vocab',
          level: 0,
          reviewCount: 10,
        ),
        const OfficialAnkiDeckNode(
          deckId: 3,
          name: 'Vocab::Chapter2',
          level: 1,
          reviewCount: 5,
        ),
      ];

      final ordered = OfficialReviewSession.orderDecksForReview(decks);

      // Deck 1 (level 0, due 10) should come before Deck 2 (level 1, due 10)
      expect(ordered.first.deckId, 1);
      expect(ordered[1].deckId, 2);
      expect(ordered[2].deckId, 3);
    });
  });
}
