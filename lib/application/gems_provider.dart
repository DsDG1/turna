// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/service/locator.dart';

enum GemEvent {
  lessonComplete(5),
  perfectLesson(10),
  streakMilestone7(50),
  streakMilestone30(200),
  streakMilestone100(500),
  achievementUnlock(25),

  /// Flat gems for finishing one SRS word-review session.
  srsReviewSession(2),

  /// Flat gems for finishing one grammar-review session.
  grammarReviewSession(2);

  final int amount;
  const GemEvent(this.amount);
}

/// Stable, privacy-safe ids for naturally idempotent gem rewards.
abstract final class GemRewardEventIds {
  static String localDay(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String lesson(String lessonId, DateTime completedAt) =>
      'earn:lesson:$lessonId:${localDay(completedAt)}';

  static String perfectLesson(String lessonId, DateTime completedAt) =>
      'earn:perfectLesson:$lessonId:${localDay(completedAt)}';

  static String achievement(String achievementId) =>
      'earn:achievement:$achievementId';

  static String reviewSession({
    required String kind,
    required DateTime completedAt,
    required String sessionSequence,
  }) =>
      'earn:${kind}Session:${localDay(completedAt)}:$sessionSequence';
}

@lazySingleton
class GemsProvider extends ChangeNotifier {
  static const int streakVoucherPrice = 60;
  static const int streakVoucherMonthlyPurchaseLimit = 2;
  final AppPrefs appPrefs;

  final StreamController<int> _gemsController =
      StreamController<int>.broadcast();

  /// Serializes mutating gem writes so concurrent callers don't race on the
  /// read-modify-write cycle for [LocalStateKeys.gems]. Achievement unlocks,
  /// lesson-complete rewards, and review-session rewards all funnel through
  /// here.
  Future<void> _writeChain = Future.value();

  /// Most recent prefs-minus-ledger difference observed during startup or
  /// restore reconciliation. Diagnostics may expose the number, never wallet
  /// contents or transaction identifiers.
  int? _lastReconciliationDifference;

  GemsProvider(this.appPrefs);

  int? get lastReconciliationDifference => _lastReconciliationDifference;

  static String localDayKey(DateTime value) =>
      GemRewardEventIds.localDay(value);

  Future<int> get streakVoucherBalance async =>
      await _resolveLedger()?.streakVoucherBalance() ?? 0;

  Future<int> streakVoucherPurchasesInMonth([DateTime? month]) async =>
      await _resolveLedger()
          ?.streakVoucherPurchasesInMonth(month ?? DateTime.now()) ??
      0;

  Future<GemConsumablePurchaseResult> purchaseStreakVoucher({
    String? idempotencyKey,
  }) async {
    final result = Completer<GemConsumablePurchaseResult>();
    await _enqueueWrite(() async {
      try {
        final ledger = _resolveLedger();
        if (ledger == null) {
          result.complete(GemConsumablePurchaseResult.insufficientFunds);
          return;
        }
        await _ensureLedgerMigrated(ledger);
        final outcome = await ledger.purchaseStreakVoucher(
          price: streakVoucherPrice,
          currentBalance: balance,
          monthlyLimit: streakVoucherMonthlyPurchaseLimit,
          idempotencyKey: idempotencyKey,
        );
        await _mirrorProjection(ledger);
        result.complete(outcome);
      } catch (_) {
        if (!result.isCompleted) {
          result.complete(GemConsumablePurchaseResult.insufficientFunds);
        }
        rethrow;
      }
    });
    return result.future;
  }

  Stream<int> getGemsStream() async* {
    yield _readInt(LocalStateKeys.gems, 0);
    yield* _gemsController.stream;
  }

  Future<void> ensureGemsInitialized() async {
    await _enqueueWrite(_initializeAndReconcile);
  }

  Future<void> earnGems(
    GemEvent event, {
    String? eventId,
    int? amount,
  }) async {
    final earned = amount ?? event.amount;
    if (earned <= 0) return;
    await _enqueueWrite(() => _recordAndMirror(
          kind: GemLedgerKind.earn,
          amount: earned,
          reason: event.name,
          eventId: eventId,
        ));
  }

  /// Single writer entry for gem balance (achievement unlocks, spends, etc.).
  /// Concurrent [addGems] calls chain via [_writeChain] so two simultaneous
  /// `+10` writes cannot lose a delta to a clobbering last-write-wins race.
  Future<void> addGems(int amount) async {
    if (amount == 0) return;
    await _enqueueWrite(() => _recordAndMirror(
          kind: amount > 0 ? GemLedgerKind.earn : GemLedgerKind.spend,
          amount: amount,
          reason: 'manual adjustment',
        ));
  }

  /// Absolute set (used by account reset). Still goes through [_writeChain]
  /// so it cannot interleave with a concurrent [addGems].
  Future<void> setGems(int value) async {
    final next = value < 0 ? 0 : value;
    await _enqueueWrite(() async {
      final ledger = _resolveLedger();
      if (ledger == null) {
        await _writeWallet(next);
        return;
      }
      await _ensureLedgerMigrated(ledger);
      final projected = await ledger.projectedBalance();
      final delta = next - projected;
      if (delta != 0) {
        await ledger.record(
          kind: GemLedgerKind.adjustment,
          amount: delta,
          reason: 'absolute wallet set',
        );
      }
      await _mirrorProjection(ledger);
    });
  }

  /// Current balance (prefs snapshot; may lag an in-flight write by one frame).
  int get balance => _readInt(LocalStateKeys.gems, 0);

  /// Deduct [amount] if the balance is sufficient. Serialized via [_writeChain]
  /// so concurrent spends cannot drive the balance negative.
  ///
  /// Returns `false` when [amount] is non-positive or the balance is too low.
  Future<bool> spendGems(int amount) async {
    if (amount <= 0) return false;
    final result = Completer<bool>();
    _writeChain = _writeChain.then((_) async {
      final current = _readInt(LocalStateKeys.gems, 0);
      if (current < amount) {
        if (!result.isCompleted) result.complete(false);
        return;
      }
      final ledger = _resolveLedger();
      if (ledger == null) {
        await _writeWallet(current - amount);
      } else {
        await _ensureLedgerMigrated(ledger);
        await ledger.record(
          kind: GemLedgerKind.spend,
          amount: -amount,
          reason: 'manual spend',
        );
        await _mirrorProjection(ledger);
      }
      if (!result.isCompleted) result.complete(true);
    }).catchError((Object e) {
      assert(() {
        // ignore: avoid_print
        print('GemsProvider spendGems failed: $e');
        return true;
      }());
      if (!result.isCompleted) result.complete(false);
    });
    return result.future;
  }

  /// Publish the preference-backed balance after an external restore.
  void refreshFromPrefs() {
    final value = _readInt(LocalStateKeys.gems, 0);
    _emit(value);
    notifyListeners();
  }

  /// Re-run the idempotent prefs migration and converge the wallet after an
  /// import or snapshot restore.
  Future<void> reconcileAfterRestore() =>
      _enqueueWrite(_initializeAndReconcile);

  /// Mirror a ledger transaction already committed by another owner (for
  /// example the atomic cosmetic purchase transaction).
  Future<void> refreshFromLedger() async {
    await _enqueueWrite(() async {
      final ledger = _resolveLedger();
      if (ledger == null) return;
      await _mirrorProjection(ledger);
    });
  }

  Future<void> _initializeAndReconcile() async {
    final ledger = _resolveLedger();
    if (ledger == null) return;
    await _ensureLedgerMigrated(ledger);

    final prefsBalance = _readInt(LocalStateKeys.gems, 0);
    final projected = await ledger.projectedBalance();
    final difference = prefsBalance - projected;
    _lastReconciliationDifference = difference;
    if (difference > 0) {
      await ledger.record(
        kind: GemLedgerKind.adjustment,
        amount: difference,
        reason: 'reconcile:prefs_above_ledger',
      );
    } else if (difference < 0) {
      // A zero-value audit fact records that reconciliation happened without
      // changing the authoritative projection.
      await ledger.record(
        kind: GemLedgerKind.adjustment,
        amount: 0,
        reason: 'reconcile:ledger_above_prefs:${-difference}',
      );
    }
    await _mirrorProjection(ledger);
  }

  Future<void> _ensureLedgerMigrated(GemLedgerDao ledger) async {
    final unlocked = appPrefs.preferences
        .getStringList(LocalStateKeys.cosmeticsUnlocked, defaultValue: const [])
        .getValue()
        .toSet()
      ..add(kAvatarRingMist);
    await ledger.migrateFromPrefs(
      prefsBalance: _readInt(LocalStateKeys.gems, 0),
      unlockedItemIds: unlocked,
    );
  }

  Future<void> _recordAndMirror({
    required GemLedgerKind kind,
    required int amount,
    required String reason,
    String? eventId,
  }) async {
    final ledger = _resolveLedger();
    if (ledger == null) {
      await _writeWallet(_readInt(LocalStateKeys.gems, 0) + amount);
      return;
    }
    await _ensureLedgerMigrated(ledger);
    await ledger.record(
      kind: kind,
      amount: amount,
      reason: reason,
      eventId: eventId,
    );
    await _mirrorProjection(ledger);
  }

  Future<void> _mirrorProjection(GemLedgerDao ledger) async {
    await _writeWallet(await ledger.projectedBalance());
  }

  Future<void> _writeWallet(int value) async {
    await appPrefs.preferences.setInt(LocalStateKeys.gems, value);
    _emit(value);
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

  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).catchError((Object e) {
      assert(() {
        // ignore: avoid_print
        print('GemsProvider write failed: $e');
        return true;
      }());
    });
    return _writeChain;
  }

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  void _emit(int newValue) {
    _gemsController.add(newValue);
  }

  @override
  void dispose() {
    _gemsController.close();
    super.dispose();
  }
}
