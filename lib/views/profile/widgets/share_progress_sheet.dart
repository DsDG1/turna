// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/profile/utils/share_image_generator.dart';
import 'package:turna/views/profile/widgets/share_progress_card.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 分享进度全局弹层（R15）：原 `ProfileAppBar` 的手写容器迁至
/// [showTurnaSheet]，分享卡的独立构图保持不变。
Future<void> showShareProgressSheet(BuildContext context) {
  return showTurnaSheet<void>(
    context: context,
    title: AppStrings.profileShareYourProgress,
    isScrollControlled: true,
    body: const _ShareProgressBody(),
    actions: const [],
  );
}

class _ShareProgressBody extends StatefulWidget {
  const _ShareProgressBody();

  @override
  State<_ShareProgressBody> createState() => _ShareProgressBodyState();
}

class _ShareProgressBodyState extends State<_ShareProgressBody> {
  final ShareProgressImageGenerator _generator = ShareProgressImageGenerator();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final LocalUser user = getIt<AppPrefs>().authUser.getValue();
    final languageProvider = context.read<LanguageProvider>();
    final gameProvider = context.read<GameProvider>();
    final gemsProvider = context.read<GemsProvider>();

    return FutureBuilder(
      future: gameProvider.getUserGameStateOnce(),
      builder: (context, stateSnapshot) {
        final gameState = stateSnapshot.data;
        final streak = gameState?.streak ?? 0;
        final totalXp = gameState?.score ?? 0;
        final completedLessons = gameState?.lessonsCompleted ?? 0;
        final perfectLessons = gameState?.perfectLessons ?? 0;

        return FutureBuilder<int>(
          future: _initialGems(gemsProvider),
          builder: (context, gemsSnapshot) {
            final gems = gemsSnapshot.data ?? 0;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                0,
                AppSpacing.pageMargin,
                AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Visible preview doubles as the capture target. The
                  // RepaintBoundary wraps the ClipRRect (not the reverse) so
                  // its layer includes the rounded-corner clip —
                  // RenderRepaintBoundary.toImage rasterizes the boundary's
                  // own subtree only and does NOT apply ancestor clips, so
                  // the boundary must be the OUTER widget for the rounded
                  // corners to appear in the captured PNG.
                  RepaintBoundary(
                    key: _generator.boundaryKey,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusXLarge),
                      child: ShareProgressCard(
                        user: user,
                        streak: streak,
                        totalXp: totalXp,
                        gems: gems,
                        completedLessons: completedLessons,
                        perfectLessons: perfectLessons,
                        targetLanguageName: languageProvider.displayName,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: TurnaTheme.brandTeal,
                      foregroundColor: TurnaTheme.textOnPrimary,
                    ),
                    onPressed: _sharing ? null : _handleShare,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: TurnaTheme.textOnPrimary,
                            ),
                          )
                        : const Icon(Icons.share_rounded),
                    label: Text(
                      _sharing
                          ? AppStrings.profileSharing
                          : AppStrings.profileShareButton,
                      style: AppTextStyles.buttonLabel,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<int> _initialGems(GemsProvider provider) async {
    // The gems stream is async*, so we take the first event as a one-off value.
    // The first event is read synchronously from prefs inside the generator,
    // so this completes immediately in practice. The timeout is a safety net
    // so a future stream implementation that never emits can't hang the
    // FutureBuilder forever — fall back to 0.
    try {
      return await provider.getGemsStream().first.timeout(
            const Duration(seconds: 1),
            onTimeout: () => 0,
          );
    } catch (_) {
      return 0;
    }
  }

  Future<void> _handleShare() async {
    setState(() => _sharing = true);
    try {
      await _generator.captureAndShare(
        shareText: AppStrings.profileShareText,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        TurnaSnackBar.show(context, AppStrings.profileShareFailed(e));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
