import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';

void main() {
  test('weekdayShortLabel maps DateTime.weekday to dayMon..daySun', () {
    expect(AppStrings.weekdayShortLabel(DateTime.monday), AppStrings.dayMon);
    expect(AppStrings.weekdayShortLabel(DateTime.wednesday), AppStrings.dayWed);
    expect(AppStrings.weekdayShortLabel(DateTime.sunday), AppStrings.daySun);
  });
}
