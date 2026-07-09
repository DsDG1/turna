// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/game_provider.dart';
import 'package:words625/application/gems_provider.dart';
import 'package:words625/application/language_provider.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/auth/local_user.dart';
import 'package:words625/routing/routing.gr.dart';
import 'package:words625/service/locator.dart';
import 'package:words625/views/profile/utils/share_image_generator.dart';
import 'package:words625/views/profile/widgets/share_progress_card.dart';
import 'package:words625/views/theme.dart';

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
        IconButton(
          icon: const Icon(Icons.settings_rounded,
              color: VarnamalaTheme.peacockTeal, size: 22),
          tooltip: 'Settings',
          onPressed: () => context.router.push(const SettingsRoute()),
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
    final SerializableFirebaseUser user =
        getIt<AppPrefs>().authUser.getValue();
    final languageProvider = context.read<LanguageProvider>();
    final gameProvider = context.read<GameProvider>();
    final gemsProvider = context.read<GemsProvider>();

    return FutureBuilder<Map<String, dynamic>>(
      future: gameProvider.getUserGameStateOnce(),
      builder: (context, stateSnapshot) {
        final gameState = stateSnapshot.data ?? const <String, dynamic>{};
        final streak = (gameState['streak'] as num?)?.toInt() ?? 0;
        final totalXp = (gameState['score'] as num?)?.toInt() ?? 0;
        final completedLessons =
            (gameState['lessonsCompleted'] as num?)?.toInt() ?? 0;
        final perfectLessons =
            (gameState['perfectLessons'] as num?)?.toInt() ?? 0;

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
                    // Visible preview
                    ClipRRect(
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
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.share_rounded),
                        label: Text(_sharing ? 'Sharing...' : 'Share'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Offstage capture target for the generator
                    _generator.captureTarget(
                      user: user,
                      streak: streak,
                      totalXp: totalXp,
                      gems: gems,
                      completedLessons: completedLessons,
                      perfectLessons: perfectLessons,
                      targetLanguage: languageProvider.selectedLanguage,
                    ),
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
    await for (final value in provider.getGemsStream()) {
      return value;
    }
    return 0;
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
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
