// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/service/locator.dart';

/// Versioned repository for the v2 achievement state document
/// (`achievements.state.v2`). All mutations go through the write chain so a
/// lesson completion racing a startup reconcile can never clobber each
/// other's unlocks.
@lazySingleton
class AchievementStateRepository {
  final AppPrefs _prefs;

  AchievementStateDocument? _cache;

  /// Serializes read-modify-write cycles on the state document.
  Future<void> _writeChain = Future.value();

  AchievementStateRepository(this._prefs);

  /// Synchronous in-memory state; empty document until first [read].
  AchievementStateDocument get current =>
      _cache ?? AchievementStateDocument.empty;

  bool get isLoaded => _cache != null;

  /// Read + decode the persisted document (cached after first call).
  Future<AchievementStateDocument> read() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = _prefs.preferences
        .getString(LocalStateKeys.achievementsStateV2, defaultValue: '')
        .getValue();
    AchievementStateDocument decoded;
    try {
      if (raw.isEmpty) {
        decoded = AchievementStateDocument.empty;
      } else {
        decoded = AchievementStateDocument.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      // Corrupt blob: start from an empty document rather than blocking the
      // whole achievement system. The v1 list stays untouched for forensics.
      logger.w('Achievement v2 state decode failed, resetting: $e');
      decoded = AchievementStateDocument.empty;
    }
    _cache = decoded;
    return decoded;
  }

  /// Atomically transform the document: the mutation runs against the newest
  /// in-chain state, so concurrent mutations compose instead of overwriting.
  Future<AchievementStateDocument> mutate(
    AchievementStateDocument Function(AchievementStateDocument current) op,
  ) {
    late AchievementStateDocument result;
    _writeChain = _writeChain.then((_) async {
      final current = await read();
      final next = op(current);
      if (identical(next, current)) {
        result = current;
        return;
      }
      _cache = next;
      await _prefs.preferences.setString(
        LocalStateKeys.achievementsStateV2,
        jsonEncode(next.toJson()),
      );
      result = next;
    }).catchError((Object e) {
      logger.w('Achievement v2 state write failed: $e');
      result = _cache ?? AchievementStateDocument.empty;
    });
    return _writeChain.then((_) => result);
  }

  /// Clear the document (account reset only — never called on metric drops).
  Future<void> clear() async {
    await mutate((_) => AchievementStateDocument.empty);
  }

  /// Drop caches after an external restore (import / Fun Lab snapshot).
  Future<void> reloadFromPrefs() async {
    await _writeChain;
    _cache = null;
    await read();
  }
}
