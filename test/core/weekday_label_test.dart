import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/l10n/app_strings.dart';

void main() {
  test('weekdayShortLabel maps DateTime.weekday to dayMon..daySun', () {
    expect(AppStrings.weekdayShortLabel(DateTime.monday), AppStrings.dayMon);
    expect(AppStrings.weekdayShortLabel(DateTime.wednesday), AppStrings.dayWed);
    expect(AppStrings.weekdayShortLabel(DateTime.sunday), AppStrings.daySun);
  });

  test('7-day rolling window labels the last bar as today', () {
    // 2026-09-16 is a Wednesday (2026-09-21 is Monday).
    final today = DateTime(2026, 9, 16);
    expect(today.weekday, DateTime.wednesday);
    final days = [
      for (var i = 6; i >= 0; i--)
        DailyStudyStats(
          date: DateTime(today.year, today.month, today.day - i),
        ),
    ];
    expect(days, hasLength(7));
    expect(
      AppStrings.weekdayShortLabel(days.last.date.weekday),
      AppStrings.dayWed,
    );
    expect(
      AppStrings.weekdayShortLabel(days.first.date.weekday),
      AppStrings.dayThu,
    );
  });
}
