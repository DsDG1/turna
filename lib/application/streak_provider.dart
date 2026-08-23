// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/gems_provider.dart';
import 'package:turna/core/streak_resolver.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Result of [StreakProvider.checkStreakOnAppOpen].
enum StreakCheckResult {
  none,
  maintained,
  broken,
}

/// Owns streak prefs and app-open / practice-day resolution.
@lazySingleton
class StreakProvider extends ChangeNotifier {
  StreakProvider(this.appPrefs);

  final AppPrefs appPrefs;

  StreakCheckResult _lastStreakCheckResult = StreakCheckResult.none;
  DateTime? _pendingProtectedDay;
  int? _pendingPreviousStreak;
  StreakCheckResult get lastStreakCheckResult => _lastStreakCheckResult;

  int get streak =>
      appPrefs.preferences.getInt(LocalStateKeys.streak, defaultValue: 0).getValue();

  String get lastStreakDateRaw => appPrefs.preferences
      .getString(LocalStateKeys.lastStreakDate, defaultValue: '')
      .getValue();

  bool get streakWasBroken => appPrefs.preferences
      .getBool(LocalStateKeys.streakWasBroken, defaultValue: false)
      .getValue();

  bool get autoUseVoucher => appPrefs.preferences
      .getBool(LocalStateKeys.streakAutoUseVoucher, defaultValue: false)
      .getValue();

  Future<void> setAutoUseVoucher(bool value) async {
    await appPrefs.preferences
        .setBool(LocalStateKeys.streakAutoUseVoucher, value);
    notifyListeners();
  }

  Set<DateTime> get protectedDays => appPrefs.preferences
      .getStringList(LocalStateKeys.streakProtectedDays, defaultValue: const [])
      .getValue()
      .map(DateTime.tryParse)
      .whereType<DateTime>()
      .map(_dateOnly)
      .toSet();

  int get protectedDaysInCurrentChain {
    if (streak <= 0) return 0;
    final last = parseDate(lastStreakDateRaw);
    if (last == null) return 0;
    final end = _dateOnly(last);
    final start = end.subtract(Duration(days: streak - 1));
    return protectedDays
        .where((day) => !day.isBefore(start) && !day.isAfter(end))
        .length;
  }

  int get realStreak => (streak - protectedDaysInCurrentChain).clamp(0, streak);
  bool get currentChainProtected => protectedDaysInCurrentChain > 0;
  bool get canProtectPendingBreak =>
      _pendingProtectedDay != null && _pendingPreviousStreak != null;
  int? get pendingPreviousStreak => _pendingPreviousStreak;

  Future<int> get voucherBalance async =>
      await _resolveLedger()?.streakVoucherBalance() ?? 0;

  DateTime? parseDate(String value) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Apply practice on [today]; persists streak fields and returns resolution.
  Future<StreakResolution> applyPracticeDay(DateTime today) async {
    final oldStreak = streak;
    final oldDate = parseDate(lastStreakDateRaw);
    final resolution = resolveStreakOnPractice(
      oldStreak: oldStreak,
      oldDate: oldDate,
      today: today,
    );

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.streak, resolution.newStreak),
      appPrefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setBool(
        LocalStateKeys.streakWasBroken,
        resolution.broken,
      ),
    ]);
    notifyListeners();
    return resolution;
  }

  Future<StreakCheckResult> checkStreakOnAppOpen() async {
    final lastDate = parseDate(lastStreakDateRaw);

    if (lastDate == null) {
      _lastStreakCheckResult = StreakCheckResult.none;
      notifyListeners();
      return _lastStreakCheckResult;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(lastDate.year, lastDate.month, lastDate.day);
    final gap = today.difference(last).inDays;

    if (gap <= 1) {
      await appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, false);
      _lastStreakCheckResult = StreakCheckResult.maintained;
      notifyListeners();
      return _lastStreakCheckResult;
    }

    // No streak to break: a fresh install (or one where the user never
    // practiced) seeds lastStreakDate=today with streak=0. Don't surface a
    // "streak broken" notice for users who never built a streak.
    if (streak == 0) {
      _lastStreakCheckResult = StreakCheckResult.none;
      notifyListeners();
      return _lastStreakCheckResult;
    }

    _pendingProtectedDay = gap == 2 ? last.add(const Duration(days: 1)) : null;
    _pendingPreviousStreak = gap == 2 ? streak : null;

    if (gap == 2 && autoUseVoucher && await voucherBalance > 0) {
      if (await protectPendingBreak()) {
        _lastStreakCheckResult = StreakCheckResult.maintained;
        notifyListeners();
        return _lastStreakCheckResult;
      }
    }

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.streak, 0),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, true),
    ]);

    _lastStreakCheckResult = StreakCheckResult.broken;
    notifyListeners();
    return _lastStreakCheckResult;
  }

  Future<bool> protectPendingBreak() async {
    final day = _pendingProtectedDay;
    final previousStreak = _pendingPreviousStreak;
    if (day == null || previousStreak == null) return false;
    final ledger = _resolveLedger();
    if (ledger == null) return false;
    final key = GemsProvider.localDayKey(day);
    final consumed = await ledger.consumeStreakVoucher(localDay: key);
    if (!consumed) return false;
    await applyProtectedDay(day, preservedStreak: previousStreak);
    _pendingProtectedDay = null;
    _pendingPreviousStreak = null;
    return true;
  }

  /// Preserve display streak only. No StudyLog, review event, dueAt, or SRS
  /// API is reachable from this method.
  Future<void> applyProtectedDay(
    DateTime day, {
    int? preservedStreak,
  }) async {
    final normalized = _dateOnly(day);
    final cutoff = normalized.subtract(const Duration(days: 89));
    final days = protectedDays.where((value) => !value.isBefore(cutoff)).toSet()
      ..add(normalized);
    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.streakProtectedDays,
        days.map((value) => value.toIso8601String()).toList(growable: false)
          ..sort(),
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.streak,
        preservedStreak ?? streak,
      ),
      appPrefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        normalized.toIso8601String(),
      ),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, false),
    ]);
    _lastStreakCheckResult = StreakCheckResult.maintained;
    notifyListeners();
  }

  GemLedgerDao? _resolveLedger() {
    if (!getIt.isRegistered<GemLedgerDao>()) return null;
    try {
      return getIt<GemLedgerDao>();
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
