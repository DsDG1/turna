import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/study_session/session_settlement_service.dart';
import 'package:turna/views/anki/components/anki_review_session_settlement.dart';

class _MockSettlementService extends SessionSettlementService {
  _MockSettlementService({this.awardedXp = 100});

  final int awardedXp;
  int callCount = 0;
  SessionSettlementSource? capturedSource;
  String? capturedSequence;
  int? capturedRemembered;
  int? capturedForgotten;
  Duration? capturedElapsed;

  @override
  Future<int> settle({
    required SessionSettlementSource source,
    required String sessionSequence,
    required int remembered,
    required int forgotten,
    required Duration elapsed,
  }) async {
    callCount++;
    capturedSource = source;
    capturedSequence = sessionSequence;
    capturedRemembered = remembered;
    capturedForgotten = forgotten;
    capturedElapsed = elapsed;
    return awardedXp;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnkiReviewSessionSettlement', () {
    testWidgets('defaults sessionSequence and startedAt', (tester) async {
      final settlement = AnkiReviewSessionSettlement();
      expect(settlement.sessionSequence, isNotEmpty);
      expect(settlement.startedAt, isNotNull);
      expect(settlement.isRecorded, isFalse);
      expect(settlement.earnedXp, equals(0));
    });

    testWidgets('no-ops when total is 0', (tester) async {
      await tester.pumpWidget(const Placeholder());
      final context = tester.element(find.byType(Placeholder));

      final mock = _MockSettlementService();
      final settlement = AnkiReviewSessionSettlement();

      final xp = await settlement.recordCompletion(
        context: context,
        total: 0,
        remembered: 0,
        forgotten: 0,
        service: mock,
      );

      expect(xp, equals(0));
      expect(settlement.isRecorded, isFalse);
      expect(settlement.earnedXp, equals(0));
      expect(mock.callCount, equals(0));
    });

    testWidgets('settles exactly once and records XP', (tester) async {
      await tester.pumpWidget(const Placeholder());
      final context = tester.element(find.byType(Placeholder));

      final mock = _MockSettlementService(awardedXp: 85);
      final startTime = DateTime(2026, 9, 16, 10, 0, 0);
      final settlement = AnkiReviewSessionSettlement(
        sessionSequence: 'custom-seq-123',
        startedAt: startTime,
      );

      final xp1 = await settlement.recordCompletion(
        context: context,
        total: 10,
        remembered: 8,
        forgotten: 2,
        elapsed: const Duration(minutes: 5),
        service: mock,
      );

      expect(xp1, equals(85));
      expect(settlement.isRecorded, isTrue);
      expect(settlement.earnedXp, equals(85));
      expect(mock.callCount, equals(1));
      expect(mock.capturedSource, equals(SessionSettlementSource.anki));
      expect(mock.capturedSequence, equals('custom-seq-123'));
      expect(mock.capturedRemembered, equals(8));
      expect(mock.capturedForgotten, equals(2));
      expect(mock.capturedElapsed, equals(const Duration(minutes: 5)));

      // Second call must be deduplicated / idempotent
      final xp2 = await settlement.recordCompletion(
        context: context,
        total: 12,
        remembered: 10,
        forgotten: 2,
        service: mock,
      );

      expect(xp2, equals(85));
      expect(mock.callCount, equals(1)); // not called again
    });
  });
}
