import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/streak_resolver.dart';

void main() {
  final today = DateTime(2026, 7, 11);

  test('null oldDate starts streak at 1 when oldStreak is 0', () {
    final r = resolveStreakOnPractice(
      oldStreak: 0,
      oldDate: null,
      today: today,
    );
    expect(r.newStreak, 1);
    expect(r.broken, isFalse);
  });

  test('null oldDate keeps non-zero streak', () {
    final r = resolveStreakOnPractice(
      oldStreak: 5,
      oldDate: null,
      today: today,
    );
    expect(r.newStreak, 5);
    expect(r.broken, isFalse);
  });

  test('same day (gap 0) does not change streak', () {
    final r = resolveStreakOnPractice(
      oldStreak: 3,
      oldDate: today,
      today: today,
    );
    expect(r.newStreak, 3);
    expect(r.broken, isFalse);
  });

  test('consecutive day (gap 1) increments streak', () {
    final r = resolveStreakOnPractice(
      oldStreak: 3,
      oldDate: today.subtract(const Duration(days: 1)),
      today: today,
    );
    expect(r.newStreak, 4);
    expect(r.broken, isFalse);
  });

  test('gap >= 2 resets streak to 1 and marks broken', () {
    final r = resolveStreakOnPractice(
      oldStreak: 10,
      oldDate: today.subtract(const Duration(days: 2)),
      today: today,
    );
    expect(r.newStreak, 1);
    expect(r.broken, isTrue);
  });
}
