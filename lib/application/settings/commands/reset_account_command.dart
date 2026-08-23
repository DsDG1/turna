// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/service/locator.dart';

/// Full account reset as one guarded, idempotent, ordered operation.
///
/// Guarantees:
///  * re-entry lock — a second [execute] while one is running fails fast
///    instead of interleaving two destructive sweeps;
///  * ordered cleanup — secondary stores first, then the atomic game-state
///    pass, then identity;
///  * every step is idempotent, so a retry after a partial failure converges
///    to the same fully-reset state;
///  * structured reporting — the UI shows exactly which scope failed.
///
/// NOT reset (kept on purpose): remote backup configuration and credentials,
/// app language, theme, accessibility settings, FSRS weights metadata
/// scopes owned by other commands.
class ResetAccountCommand {
  ResetAccountCommand();

  bool _running = false;

  bool get isRunning => _running;

  Future<SettingsOperationResult> execute() async {
    if (_running) {
      return const SettingsOperationFailure(
        code: 'accountReset.alreadyRunning',
        userMessage: '账户重置正在进行中。',
      );
    }
    _running = true;
    try {
      final mistakeProvider = getIt<MistakeProvider>();
      final srsProvider = getIt<SrsProvider>();
      final grammarProvider = getIt<GrammarReviewProvider>();
      final gameProvider = getIt<GameProvider>();
      final cosmetics = getIt<CosmeticProvider>();
      final achievements = getIt<AchievementService>();
      final appPrefs = getIt<AppPrefs>();

      // Ordered reset: clear secondary stores first, then one atomic
      // game-state pass (avoids parallel prefs races with an intermediate
      // notify), then achievements/cosmetics/identity.
      await mistakeProvider.clear();
      await srsProvider.clear();
      await grammarProvider.clear();
      await gameProvider.resetAccountGameState();
      // Achievements v2: state document, metric projection, and the
      // migration marker all reset so a post-reset account starts clean.
      await achievements.resetAll();
      await appPrefs.preferences
          .remove(LocalStateKeys.achievementsMigrationVersion);
      await cosmetics.resetCosmetics();
      await appPrefs.setLocalUser(LocalUser.local);

      return const SettingsOperationSuccess();
    } on Object catch (error) {
      return SettingsOperationFailure(
        code: 'accountReset.failed',
        userMessage: '账户重置中途失败（部分数据可能已清除）。'
            '再次执行重置即可收敛到完全重置状态。${_brief(error)}',
        retryable: true,
      );
    } finally {
      _running = false;
    }
  }

  static String _brief(Object error) {
    final firstLine = error.toString().split('\n').first;
    return firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
  }
}
