// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/auth/local_user.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/profile/utils/share_image_generator.dart';
import 'package:varnamala/views/profile/widgets/share_progress_card.dart';
import 'package:varnamala/views/theme.dart';

class ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ProfileAppBar({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: Text(
        'Profile',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.share_rounded,
              color: VarnamalaTheme.peacockTeal, size: 22),
          tooltip: 'Share',
          onPressed: () => _openShareSheet(context),
        ),
      ],
    );
  }

  void _openShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ShareProgressSheet(),
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
    final LocalUser user =
        getIt<AppPrefs>().authUser.getValue();
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
                color: VarnamalaTheme.scaffoldBg(context),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(VarnamalaTheme.radiusXLarge),
                  topRight: Radius.circular(VarnamalaTheme.radiusXLarge),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: VarnamalaTheme.dividerBg(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Share your progress',
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
                        borderRadius: BorderRadius.circular(
                            VarnamalaTheme.radiusXLarge),
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
                                  color: VarnamalaTheme.textOnPrimary,
                                ),
                              )
                            : const Icon(Icons.share_rounded),
                        label: Text(_sharing ? 'Sharing...' : 'Share'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
      await _generator.captureAndShare();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share progress: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
