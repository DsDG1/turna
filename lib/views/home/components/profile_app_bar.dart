// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/profile/utils/share_image_generator.dart';
import 'package:turna/views/profile/widgets/share_progress_card.dart';
import 'package:turna/views/theme.dart';

class ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ProfileAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  /// Opens the share-progress bottom sheet (also used from the profile hero).
  static void openShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ShareProgressSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: Text(
        AppStrings.profileTitle,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      // Share lives on the hero card; keep AppBar clean.
    );
  }
}

class _ShareProgressSheet extends StatefulWidget {
  const _ShareProgressSheet();

  @override
  State<_ShareProgressSheet> createState() => _ShareProgressSheetState();
}

class _ShareProgressSheetState extends State<_ShareProgressSheet> {
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

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TurnaTheme.scaffoldBg(context),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(TurnaTheme.radiusXLarge),
                  topRight: Radius.circular(TurnaTheme.radiusXLarge),
                ),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: TurnaTheme.dividerBg(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppStrings.profileShareYourProgress,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 20),
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
                            targetLanguage: languageProvider.selectedLanguage,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
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
                          label: Text(_sharing
                              ? AppStrings.profileSharing
                              : AppStrings.profileShareButton),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.profileShareFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
