import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CourseDatabase db;
  late GemLedgerDao ledger;
  late AppPrefs prefs;
  late StreakProvider streak;

  setUp(() async {
    ensureSqliteLibForTestHost();
    SharedPreferences.setMockInitialValues({});
    prefs = AppPrefs(await StreamingSharedPreferences.instance);
    db = CourseDatabase(NativeDatabase.memory());
    ledger = GemLedgerDao(db);
    if (getIt.isRegistered<GemLedgerDao>()) {
      await getIt.unregister<GemLedgerDao>();
    }
    getIt.registerSingleton<GemLedgerDao>(ledger);
    streak = StreakProvider(prefs);
    await prefs.preferences.setStringList(
      LocalStateKeys.streakProtectedDays,
      const [],
    );
    await prefs.preferences.setBool(LocalStateKeys.streakAutoUseVoucher, false);
  });

  tearDown(() async {
    streak.dispose();
    await getIt.unregister<GemLedgerDao>();
    await db.close();
  });

  Future<String> storageSnapshot() async {
    final srs = await db.customSelect('SELECT * FROM srs_states').get();
    final events = await db.customSelect('SELECT * FROM review_events').get();
    return jsonEncode({
      'srs': srs.map((row) => row.data).toList(),
      'events': events.map((row) => row.data).toList(),
      'studyLogs': prefs.preferences
          .getString('study.logs', defaultValue: '')
          .getValue(),
    });
  }

  test('protected day changes only streak prefs and voucher inventory',
      () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final missingDay = today.subtract(const Duration(days: 1));
    await prefs.preferences.setInt(LocalStateKeys.streak, 7);
    await prefs.preferences.setString(
      LocalStateKeys.lastStreakDate,
      today.subtract(const Duration(days: 2)).toIso8601String(),
    );
    await prefs.preferences.setString('study.logs', '{"sentinel":true}');
    await ledger.grantStreakVoucher(eventId: 'voucher:test:grant');
    final before = await storageSnapshot();

    expect(await streak.checkStreakOnAppOpen(), StreakCheckResult.broken);
    expect(streak.canProtectPendingBreak, isTrue);
    expect(await streak.protectPendingBreak(), isTrue);

    expect(await storageSnapshot(), before);
    expect(streak.streak, 7);
    expect(streak.protectedDays, contains(missingDay));
    expect(streak.currentChainProtected, isTrue);
    expect(streak.realStreak, 6,
        reason: 'protected days cannot trigger real streak achievements');
    expect(await ledger.streakVoucherBalance(), 0);
  });

  test('gap of at least two missing days does not consume', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await prefs.preferences.setInt(LocalStateKeys.streak, 5);
    await prefs.preferences.setString(
      LocalStateKeys.lastStreakDate,
      today.subtract(const Duration(days: 3)).toIso8601String(),
    );
    await prefs.preferences.setBool(LocalStateKeys.streakAutoUseVoucher, true);
    await ledger.grantStreakVoucher(eventId: 'voucher:test:gap');

    expect(await streak.checkStreakOnAppOpen(), StreakCheckResult.broken);
    expect(streak.canProtectPendingBreak, isFalse);
    expect(await ledger.streakVoucherBalance(), 1);
  });

  test('auto-use off does not consume for one missing day', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await prefs.preferences.setInt(LocalStateKeys.streak, 5);
    await prefs.preferences.setString(
      LocalStateKeys.lastStreakDate,
      today.subtract(const Duration(days: 2)).toIso8601String(),
    );
    await ledger.grantStreakVoucher(eventId: 'voucher:test:auto-off');

    expect(await streak.checkStreakOnAppOpen(), StreakCheckResult.broken);
    expect(await ledger.streakVoucherBalance(), 1);
  });

  test('no voucher does not protect one missing day', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await prefs.preferences.setInt(LocalStateKeys.streak, 5);
    await prefs.preferences.setString(
      LocalStateKeys.lastStreakDate,
      today.subtract(const Duration(days: 2)).toIso8601String(),
    );
    await prefs.preferences.setBool(LocalStateKeys.streakAutoUseVoucher, true);

    expect(await streak.checkStreakOnAppOpen(), StreakCheckResult.broken);
    expect(await ledger.streakVoucherBalance(), 0);
  });

  test('auto-use consumes one voucher for exactly one missing day', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await prefs.preferences.setInt(LocalStateKeys.streak, 4);
    await prefs.preferences.setString(
      LocalStateKeys.lastStreakDate,
      today.subtract(const Duration(days: 2)).toIso8601String(),
    );
    await prefs.preferences.setBool(LocalStateKeys.streakAutoUseVoucher, true);
    await ledger.grantStreakVoucher(eventId: 'voucher:test:auto');

    expect(await streak.checkStreakOnAppOpen(), StreakCheckResult.maintained);
    expect(streak.streak, 4);
    expect(streak.currentChainProtected, isTrue);
    expect(await ledger.streakVoucherBalance(), 0);
  });
}
